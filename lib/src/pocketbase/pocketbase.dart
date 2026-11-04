import 'dart:async';
import 'dart:collection' show SplayTreeMap;
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' show Client;
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:pocketbase_drift/pocketbase_drift.dart';

import 'services/realtime_hub.dart';

class $PocketBase extends PocketBase with WidgetsBindingObserver {
  $PocketBase(
    super.baseUrl, {
    required this.db,
    this.cacheTtl = const Duration(days: 60),
    this.requestPolicy = RequestPolicy.cacheAndNetwork,
    this.localSyncRetryCount = 5,
    this.requestTimeout = const Duration(seconds: 15),
    Duration connectivityProbeTimeout = const Duration(seconds: 5),
    Duration connectivityOnlineProbeInterval = const Duration(seconds: 60),
    Duration connectivityOfflineBackoffMin = const Duration(seconds: 5),
    Duration connectivityOfflineBackoffMax = const Duration(seconds: 60),
    super.lang,
    super.authStore,
    super.httpClientFactory,
  }) {
    connectivity = ConnectivityService(
      probe: _probeServer,
      probeTimeout: connectivityProbeTimeout,
      onlineProbeInterval: connectivityOnlineProbeInterval,
      offlineBackoffMin: connectivityOfflineBackoffMin,
      offlineBackoffMax: connectivityOfflineBackoffMax,
    );
    db.ownerResolver = () => authStore.record?.id;
    _owner = authStore.record?.id;
    _authSubscription = authStore.onChange.listen((_) => _onAuthChange());
    WidgetsBinding.instance.addObserver(this);
    connectivity.start();
    _listenForConnectivityChanges();
    // Queued changes from the last session; started here (not on the first
    // status event) so `syncCompleted` covers it right after construction.
    unawaited(syncPendingChanges());
  }

  factory $PocketBase.database(
    String baseUrl, {
    bool inMemory = false,
    String lang = "en-US",
    $AuthStore? authStore,
    DatabaseConnection? connection,
    String dbName = 'pb_drift.db',
    Duration? cacheTtl = const Duration(days: 60),
    RequestPolicy requestPolicy = RequestPolicy.cacheAndNetwork,
    Client Function()? httpClientFactory,
    int localSyncRetryCount = 5,
    Duration? requestTimeout = const Duration(seconds: 15),
    Duration connectivityProbeTimeout = const Duration(seconds: 5),
    Duration connectivityOnlineProbeInterval = const Duration(seconds: 60),
    Duration connectivityOfflineBackoffMin = const Duration(seconds: 5),
    Duration connectivityOfflineBackoffMax = const Duration(seconds: 60),
  }) {
    final db = DataBase(
      connection ?? connect(dbName, inMemory: inMemory),
    );
    final client = $PocketBase(
      baseUrl,
      db: db,
      lang: lang,
      cacheTtl: cacheTtl,
      requestPolicy: requestPolicy,
      authStore: authStore?..db = db,
      httpClientFactory: httpClientFactory,
      localSyncRetryCount: localSyncRetryCount,
      requestTimeout: requestTimeout,
      connectivityProbeTimeout: connectivityProbeTimeout,
      connectivityOnlineProbeInterval: connectivityOnlineProbeInterval,
      connectivityOfflineBackoffMin: connectivityOfflineBackoffMin,
      connectivityOfflineBackoffMax: connectivityOfflineBackoffMax,
    );
    return client;
  }

  final DataBase db;
  late final ConnectivityService connectivity;
  final Logger logger = Logger('PocketBaseDrift.client');

  /// Shares realtime subscriptions between live queries (internal).
  late final RealtimeHub realtimeHub = RealtimeHub(this);

  /// The time-to-live duration for cached records and responses.
  /// Records and responses older than this will be cleaned up when
  /// [runMaintenance] is called. Default is 60 days.
  ///
  /// If set to `null`, automatic cleanup is disabled and data is kept indefinitely.
  final Duration? cacheTtl;

  /// How many times the server may reject a pending local change (e.g. a
  /// 400 validation error) before automatic sync stops retrying it.
  ///
  /// The change is then kept with [RecordMeta.syncError], reported on
  /// [syncFailures], and can be retried with
  /// `syncPendingChanges(includeFailed: true)` or dropped with
  /// [discardPendingChange]. Default is 5.
  final int localSyncRetryCount;

  /// Maximum time for a single record request (reads of one record and
  /// writes without file uploads). When it elapses, offline-first writes
  /// are queued for sync and reads fall back to the cache. `null` disables
  /// the limit. List reads use their own `timeout` argument.
  final Duration? requestTimeout;

  /// The default [RequestPolicy] to use for all service methods.
  ///
  /// This policy is used for all CRUD operations and queries unless
  /// explicitly overridden in the method call. Defaults to
  /// `RequestPolicy.cacheAndNetwork`.
  ///
  /// Example:
  /// ```dart
  /// // Set a global default policy
  /// final client = $PocketBase.database(
  ///   'http://127.0.0.1:8090',
  ///   requestPolicy: RequestPolicy.networkFirst,
  /// );
  ///
  /// // All methods will now default to networkFirst
  /// await client.collection('posts').getFullList(); // Uses networkFirst
  ///
  /// // You can still override per-call
  /// await client.collection('posts').getFullList(
  ///   requestPolicy: RequestPolicy.cacheOnly, // Overrides global default
  /// );
  /// ```
  final RequestPolicy requestPolicy;

  StreamSubscription<LogRecord>? _logSubscription;

  set logging(bool enable) {
    hierarchicalLoggingEnabled = true;
    logger.level = enable ? Level.ALL : Level.OFF;

    if (enable) {
      // Only set up the listener if not already listening
      _logSubscription ??= Logger.root.onRecord.listen((record) {
        // Only print logs from this package's loggers
        if (record.loggerName.startsWith('PocketBaseDrift')) {
          // ignore: avoid_print
          print(
              '[${record.level.name}] ${record.loggerName}: ${record.message}');
          if (record.error != null) {
            // ignore: avoid_print
            print('  Error: ${record.error}');
          }
          if (record.stackTrace != null) {
            // ignore: avoid_print
            print('  Stack: ${record.stackTrace}');
          }
        }
      });
    } else {
      _logSubscription?.cancel();
      _logSubscription = null;
    }
  }

  StreamSubscription<bool>? _connectivitySubscription;
  StreamSubscription<AuthStoreEvent>? _authSubscription;
  final _syncFailures = StreamController<SyncFailure>.broadcast();
  bool _closed = false;

  Future<void>? _syncPass;
  bool _syncAgain = false;
  bool _syncAgainIncludeFailed = false;

  /// Completes when the running sync pass (if any) ends. Never throws.
  Future<void> get syncCompleted => _syncPass ?? Future<void>.value();

  /// Pending local changes the server rejected for good, or updates whose
  /// record was deleted on the server (see [SyncFailure.dropped]).
  Stream<SyncFailure> get syncFailures => _syncFailures.stream;

  /// Emits [failure] on [syncFailures]. Used by the services.
  void reportSyncFailure(SyncFailure failure) {
    if (!_syncFailures.isClosed) _syncFailures.add(failure);
  }

  /// Pushes all pending local changes to the server.
  ///
  /// Runs automatically when connectivity returns, when the app resumes and
  /// after login. Only one pass runs at a time: a call during a pass returns
  /// a future that completes after one more pass, so changes queued
  /// meanwhile are included. Collections are synced parents first (by
  /// relation fields), records oldest first. Never throws; rejected changes
  /// are reported on [syncFailures].
  ///
  /// [includeFailed] also retries changes parked after
  /// [localSyncRetryCount] rejections.
  Future<void> syncPendingChanges({bool includeFailed = false}) {
    if (_closed) return Future<void>.value();
    final running = _syncPass;
    if (running != null) {
      _syncAgain = true;
      _syncAgainIncludeFailed |= includeFailed;
      return running;
    }
    final pass = _syncLoop(includeFailed);
    _syncPass = pass;
    return pass;
  }

  Future<void> _syncLoop(bool includeFailed) async {
    try {
      var failed = includeFailed;
      while (true) {
        _syncAgain = false;
        _syncAgainIncludeFailed = false;
        await _syncOnce(failed);
        if (!_syncAgain || _closed || !connectivity.canReachServer) break;
        failed = _syncAgainIncludeFailed;
      }
    } finally {
      _syncPass = null;
    }
  }

  Future<void> _syncOnce(bool includeFailed) async {
    try {
      if (!connectivity.canReachServer) {
        connectivity.probeSoon();
        return;
      }
      final services = includeFailed
          ? {for (final r in await db.pendingRecords().get()) r.service}
              .toList()
          : await db.pendingServices();
      if (services.isEmpty) {
        logger.fine('No pending changes to sync.');
        return;
      }
      for (final name in await _syncOrder(services)) {
        if (_closed) return;
        await collection(name)
            .retryLocal(includeFailed: includeFailed)
            .drain<void>();
        if (!connectivity.canReachServer) return;
      }
      logger.info('Sync pass completed');
    } catch (e, st) {
      if (_closed) return;
      logger.warning('Sync pass failed', e, st);
    }
  }

  /// Orders [services] so collections referenced by relation fields sync
  /// before the collections that reference them. Cycles keep their order.
  Future<List<String>> _syncOrder(List<String> services) async {
    if (services.length < 2) return services;
    final collections = await db.allCollections();
    CollectionModel? find(String s) =>
        collections.where((c) => c.name == s || c.id == s).firstOrNull;

    final deps = <String, Set<String>>{};
    for (final s in services) {
      final targets = <String>{};
      for (final field in find(s)?.fields ?? const <CollectionField>[]) {
        if (field.type != 'relation') continue;
        final target = field.data['collectionId'];
        for (final other in services) {
          if (other != s && find(other)?.id == target) targets.add(other);
        }
      }
      deps[s] = targets;
    }

    final ordered = <String>[];
    final done = <String>{};
    var progress = true;
    while (progress && ordered.length < services.length) {
      progress = false;
      for (final s in services) {
        if (done.contains(s) || !deps[s]!.every(done.contains)) continue;
        ordered.add(s);
        done.add(s);
        progress = true;
      }
    }
    return [...ordered, ...services.where((s) => !done.contains(s))];
  }

  /// Drops the pending local change of [collectionIdOrName]/[id] (for
  /// example one the server rejected). The cached row is removed, so the
  /// next read loads the server's version.
  Future<void> discardPendingChange(
      String collectionIdOrName, String id) async {
    final row = await db.rowById(collectionIdOrName, id);
    if (row == null || !RecordMeta.isPending(row)) return;
    await db.$delete(collectionIdOrName, id);
  }

  String? _owner;

  void _onAuthChange() {
    final owner = authStore.record?.id;
    if (owner == _owner) return;
    _owner = owner;
    // Pending rows of the previous account disappear from (and those of the
    // new account reappear in) every live query.
    db.markTablesUpdated({db.services});
    if (owner != null) unawaited(syncPendingChanges());
  }

  /// Runs maintenance tasks to clean up expired cached data.
  ///
  /// This method removes:
  /// - Synced records cached more than [cacheTtl] ago (default: 60 days)
  /// - Cached responses older than [cacheTtl]
  /// - Expired file blobs, and blobs of records no longer cached
  ///
  /// You can optionally override the TTL for this specific run.
  ///
  /// **Note**: This only affects synced data. Unsynced local changes,
  /// local-only records, and pending deletions are preserved.
  ///
  /// Example:
  /// ```dart
  /// // Run maintenance with the default TTL (60 days)
  /// final result = await client.runMaintenance();
  /// print('Cleaned up ${result.totalDeleted} items');
  ///
  /// // Run with a custom TTL
  /// await client.runMaintenance(ttl: Duration(days: 7));
  /// ```
  Future<MaintenanceResult> runMaintenance({Duration? ttl}) async {
    final effectiveTtl = ttl ?? cacheTtl;

    if (effectiveTtl == null) {
      logger.info('Maintenance skipped: TTL is disabled (null)');
      return const MaintenanceResult(
        deletedRecords: 0,
        deletedResponses: 0,
        deletedFiles: 0,
      );
    }

    final cutoffDate = DateTime.now().toUtc().subtract(effectiveTtl);

    logger.info('Running maintenance (TTL: ${effectiveTtl.inDays} days)...');

    final deletedRecords =
        await db.cleanupExpiredRecords(cutoffDate: cutoffDate);
    final deletedResponses =
        await db.cleanupExpiredResponses(cutoffDate: cutoffDate);
    final deletedFiles = await db.cleanupExpiredFiles(orphanCutoff: cutoffDate);

    final result = MaintenanceResult(
      deletedRecords: deletedRecords,
      deletedResponses: deletedResponses,
      deletedFiles: deletedFiles,
    );

    if (result.totalDeleted > 0) {
      logger.info(
          'Maintenance complete: ${result.totalDeleted} items cleaned up '
          '($deletedRecords records, $deletedResponses responses, $deletedFiles files)');
    } else {
      logger.info('Maintenance complete: no expired items to clean up');
    }

    return result;
  }

  /// Lightweight reachability probe against this server's health endpoint.
  ///
  /// Used by [connectivity] as the source of truth: `connectivity_plus`
  /// reports interface events instantly, but only a request to the actual
  /// server confirms it is reachable.
  Future<bool> _probeServer() async {
    try {
      await health.check().timeout(connectivity.probeTimeout);
      return true;
    } catch (_) {
      return false;
    }
  }

  void _listenForConnectivityChanges() {
    _connectivitySubscription?.cancel();
    // The first event is the current status, handled by the start-up sync.
    _connectivitySubscription =
        connectivity.statusStream.skip(1).listen((isConnected) {
      if (!isConnected) return;
      logger.info('Server reachable. Syncing pending changes.');
      realtimeHub.scheduleRefresh();
      unawaited(syncPendingChanges());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      logger.info('App resumed. Resetting connectivity subscription.');
      connectivity.resetSubscription();
      if (connectivity.shouldAttemptNetwork) {
        unawaited(syncPendingChanges());
      }
    }
  }

  /// Generates a deterministic cache key for a given request.
  /// Returns an empty string if the request method is not 'GET',
  /// signifying that the request should not be cached.
  String _generateRequestCacheKey(
    String path, {
    String method = 'GET',
    Map<String, dynamic> query = const {},
    Map<String, dynamic> body = const {},
  }) {
    // Only cache idempotent GET requests to avoid side effects.
    if (method.toUpperCase() != 'GET') {
      return '';
    }

    // Sort maps to ensure the key is identical regardless of parameter order.
    final sortedQuery = SplayTreeMap.from(query);
    final sortedBody = SplayTreeMap.from(body);

    // Combine all unique request components into a single string.
    return '$method::$path::${jsonEncode(sortedQuery)}::${jsonEncode(sortedBody)}';
  }

  /// A list of path segments that should never be cached by [send].
  static const _nonCacheablePathSegments = [
    'api/backups',
    'api/batch',
    'api/collections',
    'api/crons',
    'api/health',
    'api/files',
    'api/logs',
    'api/realtime',
    'api/settings',
  ];

  /// Sends a single HTTP request with offline caching capabilities.
  ///
  /// This method extends the base `send` method to provide offline caching
  /// based on the provided [RequestPolicy]. Caching is enabled only for
  /// "GET" requests to custom routes. For other methods, file uploads or the
  /// built-in API, this method calls the original network-only
  /// implementation.
  @override
  Future<T> send<T extends dynamic>(
    String path, {
    String method = "GET",
    Map<String, String> headers = const {},
    Map<String, dynamic> query = const {},
    Map<String, dynamic> body = const {},
    List<http.MultipartFile> files = const [],
    RequestPolicy requestPolicy = RequestPolicy.cacheAndNetwork,
  }) async {
    final cacheKey = _generateRequestCacheKey(
      path,
      method: method,
      query: query,
      body: body,
    );

    // Bypass cache if the key is empty (not a GET request), files are present,
    // or the path contains a non-cacheable segment.
    final shouldBypassCache = _nonCacheablePathSegments.any(path.contains);
    if (cacheKey.isEmpty || files.isNotEmpty || shouldBypassCache) {
      return super.send<T>(
        path,
        method: method,
        headers: headers,
        query: query,
        body: body,
        files: files,
      );
    }

    return requestPolicy.fetch<T>(
      label: 'send-$cacheKey',
      client: this,
      remote: () => super.send<T>(
        path,
        method: method,
        headers: headers,
        query: query,
        body: body,
        files: files,
      ),
      getLocal: () async {
        final cachedJson = await db.getCachedResponse(cacheKey);
        if (cachedJson == null) {
          throw CacheMissException(
              'Response for request ($cacheKey) not found in cache.');
        }
        return jsonDecode(cachedJson) as T;
      },
      setLocal: (value) async {
        final jsonString = jsonEncode(value);
        await db.cacheResponse(cacheKey, jsonString);
      },
    );
  }

  /// Caches the collection definitions (`pb_schema.json` content) used for
  /// validation, relation expansion and file fields.
  ///
  /// Record reads and writes wait for a pending [setSchema], so an
  /// un-awaited call at startup is safe. Throws when [jsonSchema] is not a
  /// JSON list of collections.
  Future<void> setSchema(String jsonSchema) async {
    try {
      final schema = (jsonDecode(jsonSchema) as List)
          .map((item) => item as Map<String, dynamic>)
          .toList();

      // Populate the local drift database with the schema.
      await db.setSchema(schema);
    } catch (e) {
      logger.severe('Error caching schema', e);
      rethrow;
    }
  }

  final _recordServices = <String, $RecordService>{};

  @override
  $RecordService collection(String collectionIdOrName) =>
      _recordServices[collectionIdOrName] ??=
          $RecordService(this, collectionIdOrName);

  /// Get a collection by id or name and fetch
  /// the scheme to set it locally for use in
  /// validation and relations.
  ///
  /// When the server cannot provide it (offline, or no access to the
  /// collections API for regular accounts), the schema cached with
  /// [setSchema] is used; without one the error is thrown.
  Future<$RecordService> $collection(
    String collectionIdOrName, {
    RequestPolicy requestPolicy = RequestPolicy.cacheAndNetwork,
  }) async {
    final quoted = jsonEncode(collectionIdOrName);
    try {
      await collections.getFirstListItem(
        'id = $quoted || name = $quoted',
        requestPolicy: requestPolicy,
      );
    } catch (e) {
      final cached = await db.collectionByName(collectionIdOrName) ??
          await db.collectionById(collectionIdOrName);
      if (cached == null) rethrow;
      logger.fine(
          'Using the cached schema of "$collectionIdOrName" (fetch failed: $e).');
    }
    return collection(collectionIdOrName);
  }

  Selectable<Service> search(String query, {String? service}) {
    return db.search(query, service: service);
  }

  /// Creates a new batch service for executing transactional batch operations.
  ///
  /// Batch requests allow you to send multiple create, update, delete, and upsert
  /// operations in a single HTTP request to PocketBase. This is more efficient
  /// than sending individual requests and ensures atomicity on the server side.
  ///
  /// With [RequestPolicy.cacheAndNetwork] (used when calling `send()`), if the
  /// server cannot be reached, all operations are stored locally and will be
  /// retried as individual operations when connectivity is restored.
  ///
  /// Example:
  /// ```dart
  /// final batch = client.$createBatch();
  ///
  /// batch.collection('posts').create(body: {'title': 'Hello World'});
  /// batch.collection('posts').update('abc123', body: {'title': 'Updated'});
  /// batch.collection('comments').delete('def456');
  ///
  /// final results = await batch.send();
  /// for (final result in results) {
  ///   print('${result.collection}: ${result.isSuccess ? 'OK' : 'Failed'}');
  /// }
  /// ```
  $BatchService $createBatch() => $BatchService(this);

  $CollectionService? _collections;
  $FileService? _files;

  @override
  $CollectionService get collections =>
      _collections ??= $CollectionService(this);

  /// One instance per client, so concurrent downloads of a file are shared.
  @override
  $FileService get files => _files ??= $FileService(this);

  // Clean up resources
  @override
  void close() {
    if (_closed) return;
    _closed = true;
    WidgetsBinding.instance.removeObserver(this);
    _connectivitySubscription?.cancel();
    _authSubscription?.cancel();
    realtimeHub.dispose();
    connectivity.dispose();
    _logSubscription?.cancel();
    _syncFailures.close();
    db.close();
    super.close();
  }
}

/// Result of running [runMaintenance] on the PocketBase client.
///
/// Contains counts of how many items were deleted during the cleanup.
class MaintenanceResult {
  const MaintenanceResult({
    required this.deletedRecords,
    required this.deletedResponses,
    required this.deletedFiles,
  });

  /// Number of expired synced records that were deleted.
  final int deletedRecords;

  /// Number of expired cached responses that were deleted.
  final int deletedResponses;

  /// Number of expired file blobs that were deleted.
  final int deletedFiles;

  /// Total number of items deleted across all categories.
  int get totalDeleted => deletedRecords + deletedResponses + deletedFiles;

  @override
  String toString() =>
      'MaintenanceResult(records: $deletedRecords, responses: $deletedResponses, files: $deletedFiles, total: $totalDeleted)';
}
