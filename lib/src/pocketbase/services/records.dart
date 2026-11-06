import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';

import 'package:pocketbase_drift/pocketbase_drift.dart';

import 'realtime_hub.dart';
import 'sync_support.dart';

/// Represents the reactive state of a query, bundling cached data with
/// network fetching status and any error encountered during remote synchronization.
class QueryState<T> {
  const QueryState({
    required this.data,
    required this.isFetchingNetwork,
    this.error,
  });

  /// The latest cached or fetched data.
  final T data;

  /// Whether a background network request is currently active.
  final bool isFetchingNetwork;

  /// The error encountered during the most recent network fetch, if any.
  /// Cleared by the next successful fetch. An unreachable server is not an
  /// error for cache-backed queries: they keep showing the cache and
  /// refresh when the server is back.
  final Object? error;

  /// Whether an error occurred during the most recent network fetch.
  bool get hasError => error != null;

  QueryState<T> copyWith({T? data, bool? isFetchingNetwork, Object? error}) {
    return QueryState<T>(
      data: data ?? this.data,
      isFetchingNetwork: isFetchingNetwork ?? this.isFetchingNetwork,
      error: error ?? this.error,
    );
  }
}

/// Quotes [value] as a PocketBase filter string literal.
String _quote(String value) =>
    '"${value.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';

class $RecordService extends RecordService with ServiceMixin<RecordModel> {
  $RecordService(this.client, this.service) : super(client, service);

  @override
  final $PocketBase client;

  @override
  final String service;

  Selectable<RecordModel> search(String query) {
    return client.db.search(query, service: service).map(_fromRow);
  }

  RecordModel _fromRow(Service row) => itemFactoryFunc({
    ...row.data,
    'created': row.created,
    'updated': row.updated,
    'id': row.id,
  });

  /// Records of this collection with unsynced local changes (including
  /// offline deletions), oldest first. Rows the server rejected carry
  /// [RecordMeta.syncError].
  Selectable<RecordModel> pending() =>
      client.db.pendingRecords(service: service).map(_fromRow);

  /// Pushes this collection's pending local changes to the server, oldest
  /// first, and reports progress.
  ///
  /// Rows the server rejected [$PocketBase.localSyncRetryCount] times are
  /// skipped unless [includeFailed] is set (use it for a user-triggered
  /// "retry failed changes"). The pass stops early when the server becomes
  /// unreachable; the remaining rows sync on the next pass.
  Stream<RetryProgressEvent?> retryLocal({
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
    bool includeFailed = false,
  }) async* {
    final rows = await client.db.pendingRecords(service: service).get();
    final ids = [
      for (final row in rows)
        if (includeFailed || row.data[RecordMeta.syncError] == null) row.id,
    ];
    final total = ids.length;

    client.logger.info(
      'Starting retry for $total pending items in service: $service',
    );
    yield RetryProgressEvent(current: 0, total: total);

    final wait = client.requestTimeout;
    for (var i = 0; i < total; i++) {
      final push = pushPending(
        ids[i],
        query: query,
        headers: headers,
        includeFailed: includeFailed,
      );
      // Uploads have no request timeout. A stalled one keeps running (and
      // keeps its record locked) but does not hold up the other changes.
      final outcome = wait == null
          ? await push
          : await push.timeout(wait, onTimeout: () => PushOutcome.retryLater);
      yield RetryProgressEvent(current: i + 1, total: total);
      if (outcome == PushOutcome.retryLater &&
          !client.connectivity.canReachServer) {
        client.logger.info(
          'Server unreachable; ${total - i - 1} changes in $service wait for the next sync.',
        );
        return;
      }
    }

    client.logger.info('Completed retry for service: $service');
  }

  /// Subscribes to realtime events of [topic] (`*` or a record id). Events
  /// are also written to the cache, so cache watchers update.
  @override
  Future<UnsubscribeFunc> subscribe(
    String topic,
    RecordSubscriptionFunc callback, {
    String? expand,
    String? filter,
    String? fields,
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
  }) {
    final partial = fields?.isNotEmpty ?? false;
    return super.subscribe(
      topic,
      (e) async {
        await onEvent(e, partial: partial);
        callback(e);
      },
      expand: expand,
      filter: filter,
      fields: fields,
      query: query,
      headers: headers,
    );
  }

  /// Applies a realtime event to the cache.
  ///
  /// Pending local changes win (see [DataBase.upsertServerRecords]); a
  /// remote deletion of a record with a pending local edit is left to the
  /// sync, which reports it as a [SyncFailure]. Errors are logged, never
  /// thrown.
  Future<void> onEvent(
    RecordSubscriptionEvent e, {
    bool partial = false,
  }) async {
    final record = e.record;
    if (record == null) return;
    try {
      switch (e.action) {
        case 'create':
        case 'update':
          await client.db.upsertServerRecords(
            service,
            [record.toJson()],
            onlyIfNewer: true,
            partial: partial,
          );
        case 'delete':
          final row = await client.db.rowById(service, record.id);
          if (row == null) return;
          if (RecordMeta.isPending(row) &&
              !RecordMeta.flag(row[RecordMeta.deleted])) {
            return;
          }
          await client.db.$delete(service, record.id);
      }
    } catch (err, st) {
      client.logger.warning(
        'Could not apply realtime ${e.action} of $service/${record.id}',
        err,
        st,
      );
    }
  }

  // -- Live queries --------------------------------------------------------

  Future<RecordModel?> _pullOne(
    String id,
    RequestPolicy policy,
    String? expand,
    String? fields,
  ) async {
    try {
      final record = await getOne(
        id,
        expand: expand,
        fields: fields,
        requestPolicy: RequestPolicy.networkOnly,
      );
      if (policy != RequestPolicy.networkOnly) {
        await client.db.upsertServerRecords(service, [
          record.toJson(),
        ], partial: fields?.isNotEmpty ?? false);
      }
      return record;
    } on ClientException catch (e) {
      // getOne already dropped the stale cached copy.
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<List<RecordModel>> _pullList(
    RequestPolicy policy, {
    String? expand,
    String? filter,
    String? sort,
    int? limit,
    String? fields,
  }) async {
    final items = limit == null
        ? await getFullList(
            expand: expand,
            filter: filter,
            sort: sort,
            fields: fields,
            requestPolicy: RequestPolicy.networkOnly,
          )
        : (await getList(
            perPage: limit,
            skipTotal: true,
            expand: expand,
            filter: filter,
            sort: sort,
            fields: fields,
            requestPolicy: RequestPolicy.networkOnly,
          )).items;
    if (policy == RequestPolicy.networkOnly) return items;

    final json = items.map((e) => e.toJson()).toList();
    if (fields?.isNotEmpty ?? false) {
      // A projection can update cached rows but not prove deletions.
      await client.db.mergeLocal(service, json, partial: true);
    } else if (limit == null) {
      await client.db.syncLocal(service, json, filter: filter);
    } else {
      await client.db.mergeLocal(service, json);
      await _pruneWindow(items, filter: filter, sort: sort, limit: limit);
    }
    return items;
  }

  /// After a `limit` refresh: cached rows the local window shows but the
  /// server's window does not are checked on the server, and removed when
  /// they no longer exist or no longer match [filter].
  Future<void> _pruneWindow(
    List<RecordModel> serverItems, {
    String? filter,
    String? sort,
    required int limit,
  }) async {
    final serverIds = {for (final item in serverItems) item.id};
    final window = await client.db
        .$query(service, filter: filter, sort: sort, limit: limit)
        .get();
    final candidates = [
      for (final row in window)
        if (!serverIds.contains(row['id']) &&
            !RecordMeta.isPending(row) &&
            !RecordMeta.flag(row[RecordMeta.noSync]))
          row['id'] as String,
    ];
    if (candidates.isEmpty) return;
    final idFilter = candidates.map((id) => 'id = ${_quote(id)}').join(' || ');
    final still = await getFullList(
      filter: filter == null || filter.trim().isEmpty
          ? idFilter
          : '($filter) && ($idFilter)',
      fields: 'id',
      requestPolicy: RequestPolicy.networkOnly,
    );
    final keep = {for (final r in still) r.id};
    final gone = candidates.where((id) => !keep.contains(id)).toList();
    // Rows that became pending during the server check are kept.
    if (gone.isNotEmpty) await client.db.deleteSyncedRows(service, gone);
  }

  static bool _sameRecord(RecordModel a, RecordModel b) {
    if (a.id != b.id) return false;
    final da = a.data, db = b.data;
    const flags = [
      RecordMeta.synced,
      RecordMeta.deleted,
      RecordMeta.pendingRev,
      RecordMeta.retryCount,
    ];
    for (final key in flags) {
      if (da[key] != db[key]) return false;
    }
    if ((da[RecordMeta.syncError] == null) !=
        (db[RecordMeta.syncError] == null)) {
      return false;
    }
    final ua = da['updated'];
    if (ua is! String || ua.isEmpty) {
      // A `fields` projection without `updated`: compare the values.
      return jsonEncode(da) == jsonEncode(db);
    }
    if (ua != db['updated']) return false;
    final ea = da['expand'], eb = db['expand'];
    if (ea == null && eb == null) return true;
    return jsonEncode(ea) == jsonEncode(eb);
  }

  static bool _sameList(List<RecordModel> a, List<RecordModel> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_sameRecord(a[i], b[i])) return false;
    }
    return true;
  }

  static bool _sameOptional(RecordModel? a, RecordModel? b) {
    if (a == null || b == null) return a == null && b == null;
    return _sameRecord(a, b);
  }

  _LiveQuery<RecordModel?> _recordQuery(
    String id, {
    String? expand,
    String? fields,
    RequestPolicy? requestPolicy,
    required bool distinctResults,
    required bool emitStates,
  }) {
    final policy = resolvePolicy(requestPolicy);
    return _LiveQuery<RecordModel?>(
      service: this,
      policy: policy,
      topic: policy.isNetwork ? id : null,
      initial: null,
      emitStates: emitStates,
      same: distinctResults ? _sameOptional : null,
      cache: () => client.db
          .$query(
            service,
            filter: 'id = ${_quote(id)}',
            expand: expand,
            fields: fields,
          )
          .map(itemFactoryFunc)
          .watchSingleOrNull(),
      pull: () => _pullOne(id, policy, expand, fields),
      label: '$service/$id',
    );
  }

  _LiveQuery<List<RecordModel>> _listQuery({
    String? expand,
    String? filter,
    String? sort,
    int? limit,
    String? fields,
    RequestPolicy? requestPolicy,
    required bool distinctResults,
    required bool emitStates,
  }) {
    final policy = resolvePolicy(requestPolicy);
    return _LiveQuery<List<RecordModel>>(
      service: this,
      policy: policy,
      topic: policy.isNetwork ? '*' : null,
      initial: const [],
      emitStates: emitStates,
      same: distinctResults ? _sameList : null,
      cache: () => client.db
          .$query(
            service,
            filter: filter,
            expand: expand,
            sort: sort,
            limit: limit,
            fields: fields,
          )
          .map(itemFactoryFunc)
          .watch(),
      pull: () => _pullList(
        policy,
        expand: expand,
        filter: filter,
        sort: sort,
        limit: limit,
        fields: fields,
      ),
      label: '$service list',
    );
  }

  /// Watches one record.
  ///
  /// Cache-backed policies emit the cached record (null when missing) and
  /// refresh it from the server: `cacheFirst` once, `networkFirst` and
  /// `cacheAndNetwork` also on every realtime change and after a realtime
  /// reconnect. `networkOnly` emits the server's record, refetched on every
  /// realtime change, and never uses the cache. Fetch errors are emitted as
  /// stream errors; the stream stays open.
  Stream<RecordModel?> watchRecord(
    String id, {
    String? expand,
    String? fields,
    RequestPolicy? requestPolicy,
    bool distinctResults = true,
  }) => _recordQuery(
    id,
    expand: expand,
    fields: fields,
    requestPolicy: requestPolicy,
    distinctResults: distinctResults,
    emitStates: false,
  ).stream.map((s) => s.data);

  /// Watches the records matching [filter] (see [watchRecord] for the
  /// policies). With [limit], only that many records are fetched from the
  /// server (the first page of [sort]), not the whole collection.
  Stream<List<RecordModel>> watchRecords({
    String? expand,
    String? filter,
    String? sort,
    int? limit,
    String? fields,
    RequestPolicy? requestPolicy,
    bool distinctResults = true,
  }) => _listQuery(
    expand: expand,
    filter: filter,
    sort: sort,
    limit: limit,
    fields: fields,
    requestPolicy: requestPolicy,
    distinctResults: distinctResults,
    emitStates: false,
  ).stream.map((s) => s.data);

  /// Like [watchRecord], with the fetch status and last fetch error.
  Stream<QueryState<RecordModel?>> watchRecordState(
    String id, {
    String? expand,
    String? fields,
    RequestPolicy? requestPolicy,
    bool distinctResults = true,
  }) => _recordQuery(
    id,
    expand: expand,
    fields: fields,
    requestPolicy: requestPolicy,
    distinctResults: distinctResults,
    emitStates: true,
  ).stream;

  /// Like [watchRecords], with the fetch status and last fetch error.
  Stream<QueryState<List<RecordModel>>> watchRecordsState({
    String? expand,
    String? filter,
    String? sort,
    int? limit,
    String? fields,
    RequestPolicy? requestPolicy,
    bool distinctResults = true,
  }) => _listQuery(
    expand: expand,
    filter: filter,
    sort: sort,
    limit: limit,
    fields: fields,
    requestPolicy: requestPolicy,
    distinctResults: distinctResults,
    emitStates: true,
  ).stream;
}

/// One listened watch stream: a cache stream (or the server's data for
/// `networkOnly`) plus refreshes from the server.
class _LiveQuery<T> implements LiveQuery {
  _LiveQuery({
    required this.service,
    required this.policy,
    required this.topic,
    required this.initial,
    required this.emitStates,
    required this.same,
    required this.cache,
    required this.pull,
    required this.label,
  }) {
    _controller = StreamController<QueryState<T>>(
      onListen: _onListen,
      onPause: () => _cacheSubscription?.pause(),
      onResume: () => _cacheSubscription?.resume(),
      onCancel: _onCancel,
    );
  }

  final $RecordService service;
  final RequestPolicy policy;

  /// Realtime topic (`*` or a record id); null for policies without realtime.
  final String? topic;
  final T initial;

  /// Emit every state change (state streams) or only data changes.
  final bool emitStates;

  /// Data equality used to drop duplicate emissions; null emits every
  /// cache emission.
  final bool Function(T, T)? same;
  final Stream<T> Function() cache;
  final Future<T> Function() pull;
  final String label;

  late final StreamController<QueryState<T>> _controller;
  StreamSubscription<T>? _cacheSubscription;

  Stream<QueryState<T>> get stream => _controller.stream;

  $PocketBase get _client => service.client;
  bool get _networkOnly => policy == RequestPolicy.networkOnly;

  late T _data = initial;
  bool _hasData = false;
  bool _fetching = false;
  Object? _error;

  QueryState<T>? _lastState;
  bool _cancelled = false;
  bool _attached = false;
  bool _refreshing = false;
  bool _refreshAgain = false;
  bool _stale = false;
  int _fetchEpoch = -1;
  Timer? _eventDebounce;

  @override
  bool get writesCache => !_networkOnly;

  @override
  int get fetchEpoch => _fetchEpoch;

  @override
  bool get isStale => _stale;

  void _emit({bool dataChanged = false}) {
    if (_cancelled || _controller.isClosed) return;
    // Cache-backed queries wait for the first cache read, so the UI never
    // sees a placeholder value.
    if (!_hasData && (!_networkOnly || !emitStates)) return;
    final state = QueryState<T>(
      data: _data,
      isFetchingNetwork: _fetching,
      error: _error,
    );
    final last = _lastState;
    if (last != null) {
      final sameData =
          !dataChanged || (same != null && same!(last.data, state.data));
      if (emitStates) {
        if (sameData &&
            last.isFetchingNetwork == state.isFetchingNetwork &&
            identical(last.error, state.error)) {
          return;
        }
      } else if (sameData) {
        return;
      }
    }
    _lastState = state;
    _controller.add(state);
  }

  void _onListen() {
    _fetching =
        policy != RequestPolicy.cacheOnly &&
        (_networkOnly || _client.connectivity.canReachServer);
    if (!_networkOnly) {
      try {
        _cacheSubscription = cache().listen((data) {
          _data = data;
          _hasData = true;
          _emit(dataChanged: true);
        }, onError: _onCacheError);
      } catch (e, st) {
        _onCacheError(e, st);
      }
    } else {
      _emit();
    }
    unawaited(_start());
  }

  void _onCacheError(Object error, StackTrace st) {
    _client.logger.warning('Cache query for "$label" failed', error);
    _error = error;
    if (!_controller.isClosed) _controller.addError(error, st);
    // State streams report the error; data streams only get the error event.
    if (emitStates) {
      _hasData = true;
      _emit();
    }
  }

  Future<void> _start() async {
    final topic = this.topic;
    if (topic != null) {
      _attached = true;
      final attach = _client.realtimeHub.attach(service.service, topic, this);
      if (_client.connectivity.canReachServer) {
        // Subscribing before the fetch closes the gap between the two; do
        // not wait long when the server is slow or down.
        try {
          await attach.timeout(const Duration(seconds: 2));
        } on TimeoutException {
          _client.logger.fine(
            'Realtime for "$label" not ready yet; fetching anyway.',
          );
        } catch (e) {
          _client.logger.warning(
            'Realtime subscription for "$label" failed',
            e,
          );
        }
      } else {
        unawaited(
          attach.catchError((Object e) {
            _client.logger.fine('Realtime subscription for "$label" failed', e);
          }),
        );
      }
      if (_cancelled) return;
    }
    if (policy == RequestPolicy.cacheOnly) return;
    await refresh();
  }

  @override
  Future<void> refresh() async {
    if (_cancelled || policy == RequestPolicy.cacheOnly) return;
    if (_refreshing) {
      _refreshAgain = true;
      return;
    }
    if (!_networkOnly && !_client.connectivity.canReachServer) {
      // Keep showing the cache; the hub refreshes when the server is back.
      _stale = true;
      _client.connectivity.probeSoon();
      if (_fetching) {
        _fetching = false;
        _emit();
      }
      return;
    }

    _refreshing = true;
    _stale = false;
    _fetchEpoch = _client.realtimeHub.connectEpoch;
    _fetching = true;
    _emit();
    try {
      final result = await pull();
      _error = null;
      if (_networkOnly) {
        _data = result;
        _hasData = true;
        _fetching = false;
        _emit(dataChanged: true);
      }
    } catch (e, st) {
      if (!_networkOnly && isTransientError(e)) {
        _stale = true;
        _client.logger.fine('Refresh of "$label" deferred: server unreachable');
      } else {
        _error = e;
        if (!_cancelled && !_controller.isClosed) _controller.addError(e, st);
      }
    } finally {
      _refreshing = false;
      _fetching = false;
      _emit();
      if (_refreshAgain && !_cancelled) {
        _refreshAgain = false;
        unawaited(refresh());
      }
    }
  }

  @override
  void onRealtimeEvent(RecordSubscriptionEvent event) {
    // Cache-backed queries update through the cache stream.
    if (!_networkOnly || _cancelled) return;
    _eventDebounce?.cancel();
    _eventDebounce = Timer(const Duration(milliseconds: 150), refresh);
  }

  Future<void> _onCancel() async {
    _cancelled = true;
    _eventDebounce?.cancel();
    try {
      await _cacheSubscription?.cancel();
    } finally {
      final topic = this.topic;
      if (_attached && topic != null) {
        try {
          await _client.realtimeHub.detach(service.service, topic, this);
        } catch (e) {
          _client.logger.fine('Error leaving realtime for "$label"', e);
        }
      }
    }
  }
}
