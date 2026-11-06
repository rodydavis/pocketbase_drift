import 'dart:async';

import 'package:flutter/foundation.dart';
import "package:http/http.dart" as http;

import '../../../pocketbase_drift.dart';
import 'sync_support.dart';

/// Thrown by cache reads when the requested record is not cached.
class CacheMissException implements Exception {
  const CacheMissException(this.message);
  final String message;
  @override
  String toString() => 'CacheMissException: $message';
}

/// The operation of a pending local change.
enum SyncOperation { create, update, delete }

/// A pending local change that will not reach the server.
///
/// Emitted on `$PocketBase.syncFailures` when the server rejects a change
/// [RetryPolicy]-many times (the row stays in the cache with
/// [RecordMeta.syncError] and automatic sync skips it), or when an update
/// targets a record that was deleted on the server ([dropped]: the local
/// copy is removed).
class SyncFailure {
  const SyncFailure({
    required this.collection,
    required this.recordId,
    required this.operation,
    required this.error,
    this.dropped = false,
  });

  final String collection;
  final String recordId;
  final SyncOperation operation;
  final Object error;

  /// The local change was discarded because the record no longer exists on
  /// the server.
  final bool dropped;

  int? get statusCode =>
      error is ClientException ? (error as ClientException).statusCode : null;

  @override
  String toString() =>
      'SyncFailure($collection/$recordId ${operation.name}, status: $statusCode, dropped: $dropped, error: $error)';
}

/// Result of pushing one pending record to the server.
enum PushOutcome {
  /// The server accepted the change.
  synced,

  /// Nothing to push (not pending, parked, or owned by another account).
  skipped,

  /// The server was unreachable or busy; the change stays queued.
  retryLater,

  /// The server rejected the change (counted towards the retry limit).
  rejected,
}

typedef _BufferedFile = (String field, String? filename, Uint8List bytes);

mixin ServiceMixin<M extends Jsonable> on BaseCrudService<M> {
  String get service;

  @override
  $PocketBase get client;

  /// Resolves the effective request policy to use.
  ///
  /// If [methodPolicy] is explicitly provided, it takes precedence.
  /// Otherwise, the client's global [requestPolicy] is used.
  @protected
  RequestPolicy resolvePolicy(RequestPolicy? methodPolicy) =>
      methodPolicy ?? client.requestPolicy;

  String? get _owner => client.authStore.record?.id;

  String _key(String id) => '$service/$id';

  /// Whether a push or online write of [id] is running or waiting.
  bool _isPushing(String id) => isRecordBusy(client, _key(id));

  /// Runs the online write [work] of [id] after a running push of the
  /// record, so it reaches the server last (see [runOnline]).
  Future<T> _online<T>(String id, Future<T> Function() work) =>
      runOnline(client, [_key(id)], client.requestTimeout, work);

  /// Reads MultipartFiles into memory: a stream can be read only once, and
  /// queued uploads must survive until they sync.
  Future<List<_BufferedFile>> _bufferFiles(
    List<http.MultipartFile> files,
  ) async {
    if (files.isEmpty) return [];
    final buffered = <_BufferedFile>[];
    for (final file in files) {
      final bytes = await file.finalize().toBytes();
      buffered.add((file.field, file.filename, bytes));
    }
    return buffered;
  }

  List<http.MultipartFile> _multipart(List<_BufferedFile> files) => [
    for (final f in files)
      http.MultipartFile.fromBytes(f.$1, f.$3, filename: f.$2),
  ];

  /// Applies [client.requestTimeout] unless the request uploads files
  /// (large uploads on slow links legitimately take long).
  Future<T> _timed<T>(Future<T> request, {bool uploads = false}) {
    final timeout = client.requestTimeout;
    if (timeout == null || uploads) return request;
    return request.timeout(timeout);
  }

  void _reportOutcome(Object error) {
    if (isConnectivityFailure(error)) {
      client.connectivity.reportNetworkFailure();
    } else if (error is ClientException) {
      // The server answered (4xx/5xx), so it is reachable.
      client.connectivity.reportNetworkSuccess();
    }
  }

  void _requireNetwork(String operation, RequestPolicy policy) {
    if (!client.connectivity.shouldAttemptNetwork) {
      throw ClientException(
        statusCode: 0,
        response: {
          'message':
              'No network connection; ${policy.name} $operation in "$service" needs the server.',
        },
      );
    }
  }

  /// Local file names as request-body entries, keyed like the multipart
  /// parts (`images`, `images+`, ...), so the cached row lists the files.
  Map<String, dynamic> _fileBody(List<_BufferedFile> files) {
    final body = <String, List<String>>{};
    for (final f in files) {
      if (f.$2 == null) continue;
      body.putIfAbsent(f.$1, () => []).add(f.$2!);
    }
    return body;
  }

  List<Map<String, String>> _pendingFileList(List<_BufferedFile> files) => [
    for (final f in files)
      if (f.$2 != null) {'field': f.$1, 'name': f.$2!},
  ];

  Future<void> _storeBlobs(String recordId, List<_BufferedFile> files) async {
    for (final f in files) {
      if (f.$2 == null) continue;
      await _cacheFileBlob(recordId, f.$2!, f.$3);
    }
  }

  /// After the server accepted an upload, cache the bytes under the
  /// server-generated file names.
  Future<void> _cacheUploadedBlobs(
    String recordId,
    Map<String, dynamic> recordData,
    List<_BufferedFile> files,
  ) async {
    if (files.isEmpty) return;
    final byField = <String, List<_BufferedFile>>{};
    for (final f in files) {
      if (f.$2 == null) continue;
      byField.putIfAbsent(baseFieldName(f.$1), () => []).add(f);
    }
    for (final entry in byField.entries) {
      final value = recordData[entry.key];
      final names = <String>[
        if (value is String && value.isNotEmpty) value,
        if (value is List) ...value.whereType<String>(),
      ];
      final unmatched = names.toList();
      for (final f in entry.value) {
        final stem = pbFileStem(f.$2!);
        final match =
            unmatched
                .where((n) => n == f.$2 || n.startsWith('${stem}_'))
                .firstOrNull ??
            (entry.value.length == 1 && unmatched.length == 1
                ? unmatched.first
                : null);
        if (match == null) continue;
        unmatched.remove(match);
        // The server has the file; a copy above the eviction target would
        // push every other cached file out.
        if (!client.fitsFileCache(f.$3.length)) continue;
        await _cacheFileBlob(recordId, match, f.$3);
      }
    }
  }

  Future<void> _cacheFileBlob(
    String recordId,
    String filename,
    Uint8List bytes,
  ) async {
    try {
      await client.db.setFile(recordId, filename, bytes);
      client.logger.fine('Cached file blob "$filename" for record "$recordId"');
      unawaited(client.enforceFileCacheLimit());
    } catch (e) {
      client.logger.warning(
        'Error caching file blob "$filename" for record "$recordId"',
        e,
      );
    }
  }

  Future<void> _cacheServerRecord(M value, {bool partial = false}) async {
    await client.db.upsertServerRecords(service, [
      value.toJson(),
    ], partial: partial);
  }

  /// Caches the server's answer to an online update of [id] that set [body]
  /// and uploaded [files]. Queued local changes of those fields are older
  /// and no longer sync; the rest of a queued change stays pending.
  Future<void> _cacheAcceptedUpdate(
    String id,
    M value,
    Map<String, dynamic> body,
    List<_BufferedFile> files, {
    bool partial = false,
  }) => client.db.acceptServerWrite(service, id, value.toJson(), {
    // Raw keys: a modifier does not supersede a queued delta.
    ...body.keys,
    // A plain key (no `+`/`-` modifier) replaces the field's files.
    for (final f in files)
      if (baseFieldName(f.$1) == f.$1) f.$1,
  }, partial: partial);

  M _localModel(Map<String, dynamic> row) => itemFactoryFunc(row);

  // -- Reads ---------------------------------------------------------------

  @override
  Future<M> getOne(
    String id, {
    String? expand,
    String? fields,
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
    RequestPolicy? requestPolicy,
  }) async {
    final policy = resolvePolicy(requestPolicy);
    Future<M> local() async {
      final result = await client.db
          .$query(service, expand: expand, fields: fields, filter: "id = '$id'")
          .getSingleOrNull();
      if (result == null) {
        throw CacheMissException(
          'Record ($id) not found in collection $service [cache]',
        );
      }
      return itemFactoryFunc(result);
    }

    try {
      return await policy.fetch<M>(
        label: '$service/$id',
        client: client,
        remote: () => _timed(
          super.getOne(
            id,
            fields: fields,
            query: query,
            expand: expand,
            headers: headers,
          ),
        ),
        getLocal: local,
        setLocal: (value) =>
            _cacheServerRecord(value, partial: fields?.isNotEmpty ?? false),
      );
    } on ClientException catch (e) {
      if (e.statusCode != 404) rethrow;
      final row = await client.db.rowById(service, id);
      if (row != null && RecordMeta.isPending(row)) {
        // Created offline and not synced yet: this device is the source.
        if (RecordMeta.flag(row[RecordMeta.isNew]) &&
            !RecordMeta.flag(row[RecordMeta.deleted])) {
          return local();
        }
      } else if (row != null && !RecordMeta.flag(row[RecordMeta.noSync])) {
        // Deleted on the server: drop the stale copy.
        await client.db.$delete(service, id);
      }
      rethrow;
    }
  }

  @override
  Future<List<M>> getFullList({
    int batch = 1000,
    String? expand,
    String? filter,
    String? sort,
    String? fields,
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
    RequestPolicy? requestPolicy,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final policy = resolvePolicy(requestPolicy);
    final partial = fields?.isNotEmpty ?? false;
    return policy.fetch<List<M>>(
      label: '$service list',
      client: client,
      remote: () async {
        final result = <M>[];
        for (var page = 1; ; page++) {
          final list = await super
              .getList(
                page: page,
                perPage: batch,
                skipTotal: true,
                expand: expand,
                filter: filter,
                sort: sort,
                fields: fields,
                query: query,
                headers: headers,
              )
              .timeout(timeout);
          result.addAll(list.items);
          if (list.items.length < batch) return result;
        }
      },
      getLocal: () async {
        final items = await client.db
            .$query(
              service,
              expand: expand,
              fields: fields,
              filter: filter,
              sort: sort,
            )
            .get();
        return items.map(itemFactoryFunc).toList();
      },
      setLocal: (items) async {
        final json = items.map((e) => e.toJson()).toList();
        if (partial) {
          // A projection can update cached rows but not prove deletions.
          await client.db.mergeLocal(service, json, partial: true);
        } else {
          await client.db.syncLocal(service, json, filter: filter);
        }
      },
    );
  }

  @override
  Future<M> getFirstListItem(
    String filter, {
    String? expand,
    String? fields,
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
    RequestPolicy? requestPolicy,
  }) {
    final policy = resolvePolicy(requestPolicy);
    return policy.fetch<M>(
      label: service,
      client: client,
      remote: () async {
        final result = await _timed(
          super.getList(
            perPage: 1,
            skipTotal: true,
            filter: filter,
            expand: expand,
            fields: fields,
            query: query,
            headers: headers,
          ),
        );
        if (result.items.isEmpty) {
          throw ClientException(
            statusCode: 404,
            response: <String, dynamic>{
              "code": 404,
              "message": "The requested resource wasn't found.",
              "data": <String, dynamic>{},
            },
          );
        }
        return result.items.first;
      },
      getLocal: () async {
        final items = await client.db
            .$query(
              service,
              expand: expand,
              fields: fields,
              filter: filter,
              limit: 1,
            )
            .get();
        if (items.isEmpty) {
          throw CacheMissException(
            'No record matches "$filter" in collection $service [cache]',
          );
        }
        return itemFactoryFunc(items.first);
      },
      setLocal: (value) =>
          _cacheServerRecord(value, partial: fields?.isNotEmpty ?? false),
    );
  }

  /// Like [getFirstListItem], but returns null when no record matches (on
  /// the server, or in the cache when offline). Other errors are thrown.
  Future<M?> getFirstListItemOrNull(
    String filter, {
    String? expand,
    String? fields,
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
    RequestPolicy? requestPolicy,
  }) async {
    try {
      return await getFirstListItem(
        filter,
        expand: expand,
        fields: fields,
        query: query,
        headers: headers,
        requestPolicy: requestPolicy,
      );
    } catch (e) {
      if (_isNotFound(e)) return null;
      rethrow;
    }
  }

  @override
  Future<ResultList<M>> getList({
    int page = 1,
    int perPage = 30,
    bool skipTotal = false,
    String? expand,
    String? filter,
    String? sort,
    String? fields,
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
    RequestPolicy? requestPolicy,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final policy = resolvePolicy(requestPolicy);
    return policy.fetch<ResultList<M>>(
      label: '$service page $page',
      client: client,
      remote: () => super
          .getList(
            page: page,
            perPage: perPage,
            skipTotal: skipTotal,
            expand: expand,
            filter: filter,
            fields: fields,
            sort: sort,
            query: query,
            headers: headers,
          )
          .timeout(timeout),
      getLocal: () async {
        final items = await client.db
            .$query(
              service,
              limit: perPage,
              offset: (page - 1) * perPage,
              expand: expand,
              fields: fields,
              filter: filter,
              sort: sort,
            )
            .get();
        final results = items.map((e) => itemFactoryFunc(e)).toList();
        if (skipTotal) {
          return ResultList(
            page: page,
            perPage: perPage,
            items: results,
            totalItems: -1,
            totalPages: -1,
          );
        }
        final count = await client.db.$count(service, filter: filter);
        return ResultList(
          page: page,
          perPage: perPage,
          items: results,
          totalItems: count,
          totalPages: (count / perPage).ceil(),
        );
      },
      setLocal: (value) => client.db.mergeLocal(
        service,
        value.items.map((e) => e.toJson()).toList(),
        partial: fields?.isNotEmpty ?? false,
      ),
    );
  }

  /// Like [getOne], but returns null when the record does not exist (on the
  /// server, or in the cache when offline). Other errors are thrown.
  Future<M?> getOneOrNull(
    String id, {
    String? expand,
    String? fields,
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
    RequestPolicy? requestPolicy,
  }) async {
    try {
      return await getOne(
        id,
        requestPolicy: requestPolicy,
        expand: expand,
        fields: fields,
        query: query,
        headers: headers,
      );
    } catch (e) {
      if (_isNotFound(e)) return null;
      rethrow;
    }
  }

  bool _isNotFound(Object e) {
    if (e is CacheMissException) return true;
    if (e is ClientException) {
      return e.statusCode == 404 ||
          (e.statusCode == 0 && e.originalError is CacheMissException);
    }
    return false;
  }

  Future<void> setLocal(List<M> items, {bool removeAll = true}) async {
    await client.db.setLocal(
      service,
      items.map((e) => e.toJson()).toList(),
      removeAll: removeAll,
    );
  }

  // -- Writes --------------------------------------------------------------

  Future<M> _serverCreate(
    Map<String, dynamic> body,
    Map<String, dynamic> query,
    List<_BufferedFile> files,
    Map<String, String> headers,
    String? expand,
    String? fields,
  ) async {
    try {
      return await _timed(
        super.create(
          body: body,
          query: query,
          headers: headers,
          expand: expand,
          fields: fields,
          files: _multipart(files),
        ),
        uploads: files.isNotEmpty,
      );
    } catch (e) {
      // An earlier attempt created it but its response was lost.
      final id = body['id'];
      if (id is! String || !isIdConflict(e)) rethrow;
      return _timed(
        super.update(
          id,
          body: Map<String, dynamic>.of(body)..remove('id'),
          query: query,
          headers: headers,
          expand: expand,
          fields: fields,
          files: _multipart(files),
        ),
        uploads: files.isNotEmpty,
      );
    }
  }

  Future<M> _createLocal(
    Map<String, dynamic> body,
    List<_BufferedFile> files, {
    required bool sync,
  }) async {
    final row = await client.db.writeLocalCreate(
      service,
      _mergeFileNames(body, files),
      sync: sync,
      owner: _owner,
      files: sync ? _pendingFileList(files) : const [],
    );
    await _storeBlobs(row['id'] as String, files);
    return _localModel(row);
  }

  /// Writes a create to the cache only. With [sync] it is queued for the
  /// server, otherwise it stays local (`noSync`). Used by `$BatchService`.
  Future<M> writeLocalCreate(
    Map<String, dynamic> body, {
    List<(String field, String? filename, Uint8List bytes)> files = const [],
    required bool sync,
  }) => _createLocal(body, files, sync: sync);

  /// Writes an update of [id] to the cache only (see [writeLocalCreate]).
  Future<M> writeLocalUpdate(
    String id,
    Map<String, dynamic> body, {
    List<(String field, String? filename, Uint8List bytes)> files = const [],
    required bool sync,
  }) => _updateLocal(id, body, files, sync: sync);

  /// Deletes [id] in the cache only; with [sync] the deletion is queued
  /// (also for a record that is not cached). Returns false when the record
  /// is not cached and [sync] is false.
  Future<bool> writeLocalDelete(String id, {required bool sync}) =>
      client.db.writeLocalDelete(
        service,
        id,
        sync: sync,
        owner: _owner,
        createInFlight: _isPushing(id),
      );

  /// Body plus the local file names, combined per key like the server does.
  Map<String, dynamic> _mergeFileNames(
    Map<String, dynamic> body,
    List<_BufferedFile> files,
  ) {
    final merged = Map<String, dynamic>.of(body);
    _fileBody(files).forEach((key, names) {
      final existing = merged[key];
      merged[key] = [
        if (existing is String && existing.isNotEmpty) existing,
        if (existing is List) ...existing,
        ...names,
      ];
    });
    return merged;
  }

  @override
  Future<M> create({
    RequestPolicy? requestPolicy,
    Map<String, dynamic> body = const {},
    Map<String, dynamic> query = const {},
    List<http.MultipartFile> files = const [],
    Map<String, String> headers = const {},
    String? expand,
    String? fields,
  }) async {
    final policy = resolvePolicy(requestPolicy);
    final buffered = await _bufferFiles(files);
    final rawId = body['id'];
    final id = rawId is String && rawId.isNotEmpty ? rawId : newId();
    final withId = {...body, 'id': id};
    final connectivity = client.connectivity;

    switch (policy) {
      case RequestPolicy.cacheOnly:
        return _createLocal(withId, buffered, sync: false);

      case RequestPolicy.networkOnly:
        _requireNetwork('create', policy);
        try {
          final result = await _serverCreate(
            body,
            query,
            buffered,
            headers,
            expand,
            fields,
          );
          connectivity.reportNetworkSuccess();
          return result;
        } catch (e) {
          _reportOutcome(e);
          if (isConnectivityFailure(e)) throw toNetworkError(e);
          rethrow;
        }

      case RequestPolicy.networkFirst:
        _requireNetwork('create', policy);
        final M result;
        try {
          result = await _serverCreate(
            withId,
            query,
            buffered,
            headers,
            expand,
            fields,
          );
          connectivity.reportNetworkSuccess();
        } catch (e) {
          _reportOutcome(e);
          if (isConnectivityFailure(e)) throw toNetworkError(e);
          rethrow;
        }
        await _cacheServerRecord(result, partial: fields?.isNotEmpty ?? false);
        await _cacheUploadedBlobs(id, result.toJson(), buffered);
        return result;

      case RequestPolicy.cacheAndNetwork:
        if (connectivity.canReachServer) {
          try {
            final result = await _serverCreate(
              withId,
              query,
              buffered,
              headers,
              expand,
              fields,
            );
            connectivity.reportNetworkSuccess();
            await _cacheServerRecord(
              result,
              partial: fields?.isNotEmpty ?? false,
            );
            await _cacheUploadedBlobs(id, result.toJson(), buffered);
            return result;
          } catch (e) {
            _reportOutcome(e);
            if (!isTransientError(e)) rethrow;
            client.logger.info(
              'Create in $service queued for sync (server unavailable): $e',
            );
          }
        } else {
          connectivity.probeSoon();
        }
        return _createLocal(withId, buffered, sync: true);

      case RequestPolicy.cacheFirst:
        final local = await _createLocal(withId, buffered, sync: true);
        if (connectivity.canReachServer) {
          unawaited(pushPending(id));
        }
        return local;
    }
  }

  Future<M> _serverUpdate(
    String id,
    Map<String, dynamic> body,
    Map<String, dynamic> query,
    List<_BufferedFile> files,
    Map<String, String> headers,
    String? expand,
    String? fields,
  ) {
    return _timed(
      super.update(
        id,
        body: body,
        query: query,
        headers: headers,
        expand: expand,
        fields: fields,
        files: _multipart(files),
      ),
      uploads: files.isNotEmpty,
    );
  }

  Future<M> _updateLocal(
    String id,
    Map<String, dynamic> body,
    List<_BufferedFile> files, {
    required bool sync,
  }) async {
    // Uploads under a key the body also sets are combined with that value
    // (server behaviour); the others apply to the cached field value.
    final fileBody = _fileBody(files);
    final shared = fileBody.keys.where(body.containsKey).toSet();
    final row = await client.db.writeLocalUpdate(
      service,
      id,
      shared.isEmpty
          ? body
          : _mergeFileNames(
              body,
              files.where((f) => shared.contains(f.$1)).toList(),
            ),
      sync: sync,
      owner: _owner,
      fileBody: {...fileBody}..removeWhere((k, _) => shared.contains(k)),
      files: sync ? _pendingFileList(files) : const [],
    );
    await _storeBlobs(id, files);
    return _localModel(row);
  }

  /// Removes the cached copy of a record the server reports as missing,
  /// unless it holds unsynced local data.
  Future<void> _dropIfNotPending(String id) async {
    final row = await client.db.rowById(service, id);
    if (row == null) return;
    if (RecordMeta.isPending(row) || RecordMeta.flag(row[RecordMeta.noSync])) {
      return;
    }
    await client.db.$delete(service, id);
  }

  @override
  Future<M> update(
    String id, {
    RequestPolicy? requestPolicy,
    Map<String, dynamic> body = const {},
    Map<String, dynamic> query = const {},
    List<http.MultipartFile> files = const [],
    Map<String, String> headers = const {},
    String? expand,
    String? fields,
  }) async {
    // Validate that ID is not empty - calling update with an empty ID
    // would cause unpredictable behavior (server errors or creating new records).
    if (id.isEmpty) {
      throw ArgumentError.value(
        id,
        'id',
        'Cannot update a record with an empty ID in collection "$service". '
            'Ensure you have a valid record ID before calling update().',
      );
    }

    final policy = resolvePolicy(requestPolicy);
    final buffered = await _bufferFiles(files);
    final connectivity = client.connectivity;

    // The cache update runs inside the record lock too, so no push sends
    // the superseded fields in between.
    Future<M> server({required bool cacheAll}) => _online(id, () async {
      final M result;
      try {
        result = await _serverUpdate(
          id,
          body,
          query,
          buffered,
          headers,
          expand,
          fields,
        );
        connectivity.reportNetworkSuccess();
      } catch (e) {
        _reportOutcome(e);
        if (e is ClientException && e.statusCode == 404) {
          await _dropIfNotPending(id);
        }
        if (isConnectivityFailure(e)) throw toNetworkError(e);
        rethrow;
      }
      final partial = fields?.isNotEmpty ?? false;
      if (cacheAll) {
        await _cacheAcceptedUpdate(
          id,
          result,
          body,
          buffered,
          partial: partial,
        );
        await _cacheUploadedBlobs(id, result.toJson(), buffered);
      } else if (RecordMeta.isPending(
        await client.db.rowById(service, id) ?? const {},
      )) {
        // A queued change of the same fields is older than this one.
        await _cacheAcceptedUpdate(
          id,
          result,
          body,
          buffered,
          partial: partial,
        );
      }
      return result;
    });

    switch (policy) {
      case RequestPolicy.cacheOnly:
        return _updateLocal(id, body, buffered, sync: false);

      case RequestPolicy.networkOnly:
        _requireNetwork('update', policy);
        return server(cacheAll: false);

      case RequestPolicy.networkFirst:
        _requireNetwork('update', policy);
        return server(cacheAll: true);

      case RequestPolicy.cacheAndNetwork:
        final existing = await client.db.rowById(service, id);
        final pendingCreate =
            existing != null &&
            RecordMeta.isPending(existing) &&
            RecordMeta.flag(existing[RecordMeta.isNew]);
        if (pendingCreate) {
          // The server does not have it yet; the queued create carries the
          // new values.
          final local = await _updateLocal(id, body, buffered, sync: true);
          if (connectivity.canReachServer) unawaited(pushPending(id));
          return local;
        }
        if (connectivity.canReachServer) {
          try {
            return await server(cacheAll: true);
          } catch (e) {
            if (!isTransientError(e)) rethrow;
            client.logger.info(
              'Update of $service/$id queued for sync (server unavailable): $e',
            );
            if (isRecordBusyError(e)) {
              // Queued behind the running push of the record.
              final local = await _updateLocal(id, body, buffered, sync: true);
              unawaited(pushPending(id));
              return local;
            }
          }
        } else {
          connectivity.probeSoon();
        }
        return _updateLocal(id, body, buffered, sync: true);

      case RequestPolicy.cacheFirst:
        final local = await _updateLocal(id, body, buffered, sync: true);
        if (connectivity.canReachServer) unawaited(pushPending(id));
        return local;
    }
  }

  @override
  Future<void> delete(
    String id, {
    RequestPolicy? requestPolicy,
    Map<String, dynamic> body = const {},
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
  }) async {
    final policy = resolvePolicy(requestPolicy);
    final connectivity = client.connectivity;

    // The cache update runs inside the record lock too, so no push sends
    // the deleted record's queued change in between.
    Future<void> server({required bool cache}) => _online(id, () async {
      try {
        await _timed(
          super.delete(id, body: body, query: query, headers: headers),
        );
        connectivity.reportNetworkSuccess();
      } catch (e) {
        _reportOutcome(e);
        if (cache && e is ClientException && e.statusCode == 404) {
          await client.db.$delete(service, id);
        }
        if (isConnectivityFailure(e)) throw toNetworkError(e);
        rethrow;
      }
      if (cache) await client.db.$delete(service, id);
    });

    switch (policy) {
      case RequestPolicy.cacheOnly:
        await writeLocalDelete(id, sync: false);
        return;

      case RequestPolicy.networkOnly:
        _requireNetwork('delete', policy);
        await server(cache: false);
        return;

      case RequestPolicy.networkFirst:
        _requireNetwork('delete', policy);
        await server(cache: true);
        return;

      case RequestPolicy.cacheAndNetwork:
        final existing = await client.db.rowById(service, id);
        if (existing != null &&
            RecordMeta.isPending(existing) &&
            RecordMeta.flag(existing[RecordMeta.isNew])) {
          // Not on the server yet: removed locally, or queued as a deletion
          // when its create is being pushed right now.
          await writeLocalDelete(id, sync: true);
          if (_isPushing(id)) unawaited(pushPending(id));
          return;
        }
        var busy = false;
        if (connectivity.canReachServer) {
          try {
            await server(cache: true);
            return;
          } on ClientException catch (e) {
            if (e.statusCode == 404) return;
            if (!isTransientError(e)) rethrow;
            busy = isRecordBusyError(e);
          } catch (e) {
            if (!isTransientError(e)) rethrow;
          }
        } else {
          connectivity.probeSoon();
        }
        await writeLocalDelete(id, sync: true);
        // Queued behind the running push of the record.
        if (busy) unawaited(pushPending(id));
        return;

      case RequestPolicy.cacheFirst:
        await writeLocalDelete(id, sync: true);
        if (connectivity.canReachServer) unawaited(pushPending(id));
        return;
    }
  }

  // -- Sync ----------------------------------------------------------------

  Future<Set<String>> _fileFieldNames() async {
    final collection = await client.db.collectionByName(service);
    return {
      for (final f in collection?.fields ?? const <CollectionField>[])
        if (f.type == 'file') f.name,
    };
  }

  Set<String> _pendingFileNames(Map<String, dynamic> row) => {
    for (final f in (row[RecordMeta.pendingFiles] as List? ?? const []))
      if (f is Map && f['name'] is String) f['name'] as String,
  };

  Future<List<http.MultipartFile>> _pendingParts(
    String id,
    Map<String, dynamic> row,
    Set<String> fileFields,
  ) async {
    final parts = <http.MultipartFile>[];
    final pending = row[RecordMeta.pendingFiles];
    if (pending is List) {
      for (final f in pending) {
        if (f is! Map || f['name'] is! String || f['field'] is! String) {
          continue;
        }
        final blob = await client.db
            .getFile(id, f['name'] as String)
            .getSingleOrNull();
        if (blob == null) {
          client.logger.warning(
            'Pending upload "${f['name']}" of $service/$id has no cached bytes; skipped.',
          );
          continue;
        }
        parts.add(
          http.MultipartFile.fromBytes(
            f['field'] as String,
            blob.data,
            filename: blob.filename,
          ),
        );
      }
      return parts;
    }
    // Rows queued by older versions: a create uploads every cached blob its
    // file fields reference.
    if (!RecordMeta.flag(row[RecordMeta.isNew])) return parts;
    final blobs = {
      for (final b in await client.db.getFilesForRecord(id).get())
        b.filename: b,
    };
    for (final field in fileFields) {
      final value = row[field];
      final names = <String>[
        if (value is String && value.isNotEmpty) value,
        if (value is List) ...value.whereType<String>(),
      ];
      for (final name in names) {
        final blob = blobs[name];
        if (blob == null) continue;
        parts.add(
          http.MultipartFile.fromBytes(
            field,
            blob.data,
            filename: blob.filename,
          ),
        );
      }
    }
    return parts;
  }

  Map<String, dynamic> _syncBody(
    Map<String, dynamic> row,
    Set<String> fileFields, {
    required bool create,
  }) {
    final localFiles = _pendingFileNames(row);
    final changed = create ? null : row[RecordMeta.pendingFields];
    final keys = changed is List
        ? changed.whereType<String>()
        : row.keys.where(
            (k) =>
                !RecordMeta.keys.contains(k) &&
                !RecordMeta.systemKeys.contains(k),
          );
    final base = changed is List ? row[RecordMeta.pendingBase] : null;
    final kinds = changed is List ? row[RecordMeta.pendingDeltas] : null;
    final body = <String, dynamic>{};
    for (final key in keys) {
      final Object? value;
      if (fileFields.contains(key)) {
        // New files travel as multipart parts; legacy rows never resend the
        // record's existing files.
        if (create || changed is! List) continue;
        final local = row[key];
        value = local is List
            ? local
                  .whereType<String>()
                  .where((n) => !localFiles.contains(n))
                  .toList()
            : (local is String && localFiles.contains(local) ? '' : local);
      } else {
        value = row[key];
      }
      // Modifier-only edits send their change, so concurrent changes of the
      // field on the server survive.
      final kind = kinds is Map ? kinds[key] : null;
      final delta = kind is String && base is Map && base.containsKey(key)
          ? deltaBody(
              key,
              kind,
              base[key],
              value,
              files: fileFields.contains(key),
            )
          : null;
      if (delta != null) {
        body.addAll(delta);
      } else {
        body[key] = value;
      }
    }
    return body;
  }

  List<Map<String, dynamic>> _sentFiles(List<http.MultipartFile> parts) => [
    for (final p in parts)
      if (p.filename != null) {'field': p.field, 'name': p.filename},
  ];

  /// Pushes the pending local change of record [id] to the server.
  ///
  /// Sends only the fields changed locally (updates), the whole record
  /// (creates) or the deletion. On success the cached row takes the server's
  /// version (keeping any change made while the request was in flight).
  /// Rejections count towards `localSyncRetryCount`; at the limit the row
  /// is parked with [RecordMeta.syncError] and a [SyncFailure] is emitted.
  ///
  /// Pushes of one record run one at a time: a call made while another is
  /// running waits for it and then pushes whatever is still pending.
  Future<PushOutcome> pushPending(
    String id, {
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
    bool includeFailed = false,
  }) {
    return runForRecords(
      client,
      [_key(id)],
      () => _push(
        id,
        query: query,
        headers: headers,
        includeFailed: includeFailed,
      ),
    );
  }

  /// [_timed] for pushes. After a timeout the push keeps its record locked
  /// until the request itself settles (at most 3 × `requestTimeout` more),
  /// so a newer write of the record cannot reach the server before it.
  Future<T> _timedPush<T>(Future<T> request, {bool uploads = false}) async {
    final timeout = client.requestTimeout;
    if (timeout == null || uploads) return request;
    try {
      return await request.timeout(timeout);
    } on TimeoutException {
      await request
          .then<void>((_) {}, onError: (Object _) {})
          .timeout(timeout * 3, onTimeout: () {});
      rethrow;
    }
  }

  Future<PushOutcome> _push(
    String id, {
    required Map<String, dynamic> query,
    required Map<String, String> headers,
    required bool includeFailed,
  }) async {
    final row = await client.db.rowById(service, id);
    if (row == null || !RecordMeta.isPending(row)) return PushOutcome.skipped;
    if (!includeFailed && row[RecordMeta.syncError] != null) {
      return PushOutcome.skipped;
    }
    final owner = row[RecordMeta.pendingOwner];
    if (owner != null && owner != _owner) return PushOutcome.skipped;

    final rev = (row[RecordMeta.pendingRev] as num?)?.toInt();
    // A `fields` projection returns only part of the record.
    final partial = '${query['fields'] ?? ''}'.isNotEmpty;
    final operation = RecordMeta.flag(row[RecordMeta.deleted])
        ? SyncOperation.delete
        : RecordMeta.flag(row[RecordMeta.isNew])
        ? SyncOperation.create
        : SyncOperation.update;
    try {
      switch (operation) {
        case SyncOperation.delete:
          try {
            await _timedPush(super.delete(id, query: query, headers: headers));
          } on ClientException catch (e) {
            if (e.statusCode != 404) rethrow;
          }
          await client.db.$delete(service, id);
        case SyncOperation.create:
          final fileFields = await _fileFieldNames();
          final parts = await _pendingParts(id, row, fileFields);
          final body = _syncBody(row, fileFields, create: true);
          M result;
          try {
            result = await _timedPush(
              super.create(
                body: {...body, 'id': id},
                files: parts,
                query: query,
                headers: headers,
              ),
              uploads: parts.isNotEmpty,
            );
          } catch (e) {
            if (!isIdConflict(e)) rethrow;
            result = await _timedPush(
              super.update(
                id,
                body: body,
                files: await _pendingParts(id, row, fileFields),
                query: query,
                headers: headers,
              ),
              uploads: parts.isNotEmpty,
            );
          }
          await client.db.completePendingSync(
            service,
            id,
            rev,
            result.toJson(),
            sentFiles: _sentFiles(parts),
            sentBody: body,
            partial: partial,
          );
        case SyncOperation.update:
          final fileFields = await _fileFieldNames();
          final parts = await _pendingParts(id, row, fileFields);
          final body = _syncBody(row, fileFields, create: false);
          final result = await _timedPush(
            super.update(
              id,
              body: body,
              files: parts,
              query: query,
              headers: headers,
            ),
            uploads: parts.isNotEmpty,
          );
          await client.db.completePendingSync(
            service,
            id,
            rev,
            result.toJson(),
            sentFiles: _sentFiles(parts),
            sentBody: body,
            partial: partial,
          );
      }
      client.connectivity.reportNetworkSuccess();
      client.logger.fine('Synced ${operation.name} of $service/$id');
      return PushOutcome.synced;
    } catch (e) {
      _reportOutcome(e);
      if (isTransientError(e) ||
          (e is ClientException && e.statusCode == 401)) {
        client.logger.fine('Sync of $service/$id deferred: $e');
        return PushOutcome.retryLater;
      }
      if (operation == SyncOperation.update &&
          e is ClientException &&
          e.statusCode == 404) {
        // Deleted on the server: the edit cannot apply anymore.
        await client.db.$delete(service, id);
        client.logger.warning(
          '$service/$id no longer exists on the server; dropped the local edit.',
        );
        client.reportSyncFailure(
          SyncFailure(
            collection: service,
            recordId: id,
            operation: operation,
            error: e,
            dropped: true,
          ),
        );
        return PushOutcome.rejected;
      }
      final retries = ((row[RecordMeta.retryCount] as num?)?.toInt() ?? 0) + 1;
      final parked = retries >= client.localSyncRetryCount;
      final recorded = await client.db.markSyncFailure(
        service,
        id,
        sentRev: rev,
        retryCount: retries,
        error: parked
            ? {
                'status': e is ClientException ? e.statusCode : null,
                'message': e is ClientException ? e.response['message'] : '$e',
                'data': e is ClientException ? e.response['data'] : null,
                'at': pbTimestamp(),
              }
            : null,
      );
      client.logger.warning(
        'Sync of ${operation.name} $service/$id rejected ($retries/${client.localSyncRetryCount})',
        e,
      );
      // Not recorded: the row changed meanwhile and the newer change is
      // still queued, so nothing was rejected for good.
      if (parked && recorded) {
        client.reportSyncFailure(
          SyncFailure(
            collection: service,
            recordId: id,
            operation: operation,
            error: e,
          ),
        );
      }
      return PushOutcome.rejected;
    }
  }
}

class RetryProgressEvent {
  final int total;
  final int current;

  const RetryProgressEvent({required this.total, required this.current});

  double get progress => total == 0 ? 1 : current / total;
}

/// Defines how data should be fetched and synchronized between local cache and remote server.
///
/// For read operations (GET):
/// - [cacheOnly]: Only read from cache, never contact server
/// - [networkOnly]: Only read from server, never use cache
/// - [cacheFirst]: Return cache immediately and refresh it in the background;
///   on a cache miss, wait for the server
/// - [networkFirst]: Try network first, fallback to cache if the server is
///   unreachable
/// - [cacheAndNetwork]: Same as [networkFirst] for one-time reads; streams
///   emit the cache first, then the refreshed data
///
/// Server answers (4xx such as 403/404) are never replaced by cached data:
/// they are thrown as [ClientException].
///
/// For write operations (CREATE/UPDATE/DELETE):
/// - [cacheOnly]: Write to cache only with noSync flag (never syncs to server)
/// - [networkOnly]: Write to server only, throw error if fails
/// - [cacheFirst]: Write to cache first, then try server in background
/// - [networkFirst]: Write to server first, then update cache (strict, no fallback)
/// - [cacheAndNetwork]: Try server; queue locally only when the server is
///   unreachable (offline-first). Rejections are thrown.
enum RequestPolicy {
  cacheOnly,
  networkOnly,
  cacheFirst,
  networkFirst,
  cacheAndNetwork,
}

extension RequestPolicyUtils on RequestPolicy {
  /// Returns true if the policy performs a synchronous network operation
  /// that blocks and returns network data immediately.
  ///
  /// Note: `cacheFirst` is not included even though it syncs to network in background,
  /// because it returns cache data immediately without waiting for network.
  bool get isNetwork =>
      this == RequestPolicy.networkOnly ||
      this == RequestPolicy.networkFirst ||
      this == RequestPolicy.cacheAndNetwork;

  /// Returns true if the policy reads from or writes to cache.
  bool get isCache =>
      this == RequestPolicy.cacheOnly ||
      this == RequestPolicy.cacheFirst ||
      this == RequestPolicy.networkFirst ||
      this == RequestPolicy.cacheAndNetwork;

  /// Fetch data for read operations (GET requests).
  ///
  /// [getLocal] should throw [CacheMissException] when nothing is cached.
  /// Only an unreachable server falls back to the cache; server answers
  /// (4xx) are rethrown. When neither source has the data, a
  /// [ClientException] with status 0 is thrown.
  Future<T> fetch<T>({
    required String label,
    required $PocketBase client,
    required Future<T> Function() remote,
    required Future<T> Function() getLocal,
    required Future<void> Function(T) setLocal,
  }) async {
    client.logger.finer('Fetching "$label" with policy "$name"');

    return switch (this) {
      RequestPolicy.cacheOnly => getLocal(),
      RequestPolicy.networkOnly => _fetchNetworkOnly(label, client, remote),
      RequestPolicy.cacheFirst => _fetchCacheFirst(
        label,
        client,
        remote,
        getLocal,
        setLocal,
      ),
      RequestPolicy.networkFirst => _fetchNetworkFirst(
        label,
        client,
        remote,
        getLocal,
        setLocal,
      ),
      RequestPolicy.cacheAndNetwork => _fetchNetworkFirst(
        label,
        client,
        remote,
        getLocal,
        setLocal,
      ),
    };
  }

  Future<T> _remote<T>($PocketBase client, Future<T> Function() remote) async {
    try {
      final result = await remote();
      client.connectivity.reportNetworkSuccess();
      return result;
    } catch (e) {
      if (isConnectivityFailure(e)) {
        client.connectivity.reportNetworkFailure();
      } else if (e is ClientException) {
        client.connectivity.reportNetworkSuccess();
      }
      if (isTransientError(e)) throw toNetworkError(e);
      rethrow;
    }
  }

  Future<void> _safeSetLocal<T>(
    String label,
    $PocketBase client,
    Future<void> Function(T) setLocal,
    T value,
  ) async {
    try {
      await setLocal(value);
    } catch (e) {
      client.logger.warning('Failed to update cache for "$label".', e);
    }
  }

  Future<T> _fetchNetworkOnly<T>(
    String label,
    $PocketBase client,
    Future<T> Function() remote,
  ) async {
    if (!client.connectivity.shouldAttemptNetwork) {
      throw ClientException(
        statusCode: 0,
        response: {
          'message': 'No network connection for "$label" (networkOnly).',
        },
      );
    }
    return _remote(client, remote);
  }

  Future<T> _fetchCacheFirst<T>(
    String label,
    $PocketBase client,
    Future<T> Function() remote,
    Future<T> Function() getLocal,
    Future<void> Function(T) setLocal,
  ) async {
    late T cached;
    var hit = false;
    try {
      cached = await getLocal();
      hit = true;
    } on CacheMissException {
      hit = false;
    }

    if (!hit) {
      // Nothing to show yet: wait for the server.
      return _fetchNetworkFirst(
        label,
        client,
        remote,
        getLocal,
        setLocal,
        skipCache: true,
      );
    }

    if (client.connectivity.canReachServer) {
      unawaited(
        _remote(client, remote)
            .then((value) => _safeSetLocal(label, client, setLocal, value))
            .catchError((Object e) {
              client.logger.fine('Background refresh of "$label" failed.', e);
            }),
      );
    }
    return cached;
  }

  Future<T> _fetchNetworkFirst<T>(
    String label,
    $PocketBase client,
    Future<T> Function() remote,
    Future<T> Function() getLocal,
    Future<void> Function(T) setLocal, {
    bool skipCache = false,
  }) async {
    final connectivity = client.connectivity;
    Object? networkError;
    var attempted = false;

    Future<T> fromNetwork() async {
      attempted = true;
      final result = await _remote(client, remote);
      await _safeSetLocal(label, client, setLocal, result);
      return result;
    }

    if (connectivity.canReachServer) {
      try {
        return await fromNetwork();
      } on ClientException catch (e) {
        if (!isTransientError(e)) rethrow;
        networkError = e;
      }
    }

    Object? cacheError;
    if (!skipCache) {
      try {
        return await getLocal();
      } catch (e) {
        cacheError = e;
      }
    }

    // Believed offline and not cached: try the server as a last resort.
    if (!attempted && connectivity.shouldAttemptNetwork) {
      try {
        return await fromNetwork();
      } on ClientException catch (e) {
        if (!isTransientError(e)) rethrow;
        networkError = e;
      }
    }

    if (cacheError != null && cacheError is! CacheMissException) {
      client.logger.warning('Cache read for "$label" failed.', cacheError);
      if (networkError == null) throw cacheError;
    }
    if (networkError != null) throw networkError;
    throw ClientException(
      statusCode: 0,
      originalError: cacheError,
      response: {'message': 'Offline and "$label" is not cached.'},
    );
  }
}
