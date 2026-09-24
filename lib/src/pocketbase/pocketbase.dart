import 'dart:async';
import 'dart:collection' show SplayTreeMap;
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:pocketbase_drift/pocketbase_drift.dart';

class $PocketBase extends PocketBase with WidgetsBindingObserver {
  $PocketBase(
    super.baseUrl, {
    required this.db,
    this.cacheTtl = const Duration(days: 60),
    this.requestPolicy = RequestPolicy.cacheAndNetwork,
    this.localSyncRetryCount = 5,
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
    WidgetsBinding.instance.addObserver(this);
    connectivity.start();
    _listenForConnectivityChanges();
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

  /// The time-to-live duration for cached records and responses.
  /// Records and responses older than this will be cleaned up when
  /// [runMaintenance] is called. Default is 60 days.
  ///
  /// If set to `null`, automatic cleanup is disabled and data is kept indefinitely.
  final Duration? cacheTtl;

  /// The number of times to retry a failed local sync before deleting the record.
  ///
  /// This applies to records that fail server validation (e.g. 400 errors).
  /// Default is 5.
  final int localSyncRetryCount;

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

  StreamSubscription? _connectivitySubscription;

  // Add a completer to track sync completion
  // Initialize to an already completed state.
  Completer<void>? _syncCompleter = Completer<void>()..complete();

  // Public getter to await sync completion
  Future<void> get syncCompleted => _syncCompleter?.future ?? Future.value();

  /// Runs maintenance tasks to clean up expired cached data.
  ///
  /// This method removes:
  /// - Synced records older than [cacheTtl] (default: 60 days)
  /// - Cached responses older than [cacheTtl]
  /// - Expired file blobs
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
    final deletedFiles = await db.cleanupExpiredFiles();

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
    _connectivitySubscription = connectivity.statusStream.listen((isConnected) {
      if (isConnected) {
        logger
            .info('Connectivity restored. Retrying all pending local changes.');
        _retrySyncForAllServices();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      logger.info('App resumed. Resetting connectivity subscription.');
      connectivity.resetSubscription();
      // After resetting, the subscription will get the current state.
      // We can also trigger a proactive sync if online.
      if (connectivity.shouldAttemptNetwork) {
        logger.info(
            'App resumed and online. Checking for pending changes to sync.');
        _retrySyncForAllServices();
      }
    }
  }

  Future<void> _retrySyncForAllServices() async {
    // A sync is starting, create a new, un-completed completer.
    _syncCompleter = Completer<void>();

    try {
      // Query database to find services with pending records
      // This ensures we sync even if service instances haven't been created yet
      // Note: In SQLite, JSON booleans are stored as 0 (false) and 1 (true)
      final pendingServicesQuery = await db
          .customSelect("SELECT DISTINCT service FROM services WHERE "
              "json_extract(data, '\$.synced') = 0 AND "
              "(json_extract(data, '\$.noSync') IS NULL OR json_extract(data, '\$.noSync') = 0)")
          .get();

      if (pendingServicesQuery.isEmpty) {
        logger.info('No pending changes to sync.');
        _syncCompleter!.complete();
        return;
      }

      final futures = <Future<void>>[];

      // Initialize service instances and sync for each service with pending records
      for (final row in pendingServicesQuery) {
        final serviceName = row.read<String>('service');

        // Skip schema and any other system services
        if (serviceName == 'schema') continue;

        // Get or create the service instance (this populates _recordServices)
        final service = collection(serviceName);

        // Convert stream to future and collect all sync operations
        final future = service.retryLocal().last.then((_) {
          logger.fine('Sync completed for service: $serviceName');
        });
        futures.add(future);
      }

      if (futures.isEmpty) {
        logger.info('No services to sync (only system records pending).');
        _syncCompleter!.complete();
        return;
      }

      // Wait for all services to complete their sync
      await Future.wait(futures);
      logger.info('All sync operations completed successfully');

      _syncCompleter!.complete();
    } catch (e) {
      logger.severe('Error during sync operations', e);
      if (!(_syncCompleter?.isCompleted ?? true)) {
        _syncCompleter!.completeError(e);
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
  /// "GET" requests. For other methods, or if files are being uploaded,
  /// this method calls the original network-only implementation.
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
          throw Exception(
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

  Future<void> setSchema(String jsonSchema) async {
    try {
      final schema = (jsonDecode(jsonSchema) as List)
          .map((item) => item as Map<String, dynamic>)
          .toList();

      // Populate the local drift database with the schema.
      await db.setSchema(schema);
    } catch (e) {
      logger.severe('Error caching schema', e);
    }
  }

  final _recordServices = <String, $RecordService>{};

  @override
  $RecordService collection(String collectionIdOrName) {
    var service = _recordServices[collectionIdOrName];

    if (service == null) {
      service = $RecordService(this, collectionIdOrName);
      _recordServices[collectionIdOrName] = service;
    }

    return service;
  }

  /// Get a collection by id or name and fetch
  /// the scheme to set it locally for use in
  /// validation and relations
  Future<$RecordService> $collection(
    String collectionIdOrName, {
    RequestPolicy requestPolicy = RequestPolicy.cacheAndNetwork,
  }) async {
    await collections.getFirstListItem(
      'id = "$collectionIdOrName" || name = "$collectionIdOrName"',
      requestPolicy: requestPolicy,
    );

    var service = _recordServices[collectionIdOrName];

    if (service == null) {
      service = $RecordService(this, collectionIdOrName);
      _recordServices[collectionIdOrName] = service;
    }

    return service;
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
  /// batch fails due to network issues, all operations are stored locally and
  /// will be retried as individual operations when connectivity is restored.
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

  @override
  $CollectionService get collections => $CollectionService(this);

  @override
  $FileService get files => $FileService(this);

  // Clean up resources
  @override
  void close() {
    WidgetsBinding.instance.removeObserver(this);
    _connectivitySubscription?.cancel();
    connectivity.dispose();
    _logSubscription?.cancel();
    db.close();
    super.close();
  }

  // @override
  // $AdminsService get admins => $AdminsService(this);

  // @override
  // $RealtimeService get realtime => $RealtimeService(this);

  // @override
  // $SettingsService get settings => $SettingsService(this);

  // @override
  // $LogService get logs => $LogService(this);

  // @override
  // $HealthService get health => $HealthService(this);

  // @override
  // $BackupService get backups => $BackupService(this);
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
