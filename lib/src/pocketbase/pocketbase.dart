import 'dart:async';
import 'package:drift/drift.dart';
import 'package:http/http.dart';
import 'package:logging/logging.dart';
import 'package:pocketbase_drift/pocketbase_drift.dart';

class $PocketBase extends PocketBase {
  $PocketBase(
    super.baseUrl, {
    required this.db, // Receive the db instance
    super.lang,
    super.authStore,
    super.httpClientFactory,
  }) : connectivity = ConnectivityService() {
    _listenForConnectivityChanges(); // Setup listener after initialization
  }

  factory $PocketBase.database(
    String baseUrl, {
    bool inMemory = false,
    bool autoLoad = true,
    String lang = "en-US",
    AuthStore? authStore,
    DatabaseConnection? connection,
    String dbName = 'files',
    Client Function()? httpClientFactory,
  }) {
    return $PocketBase(
      baseUrl,
      db: DataBase(
        connection ?? connect(dbName, inMemory: inMemory),
      ),
      lang: lang,
      authStore: authStore,
      httpClientFactory: httpClientFactory,
    );
  }

  final DataBase db;
  final ConnectivityService connectivity;
  final Logger logger = Logger('PocketBaseDrift.client');

  set logging(bool enable) {
    hierarchicalLoggingEnabled = true;
    logger.level = enable ? Level.ALL : Level.OFF;
  }

  StreamSubscription? _connectivitySubscription;

  // Add a completer to track sync completion
  // Initialize to an already completed state.
  Completer<void>? _syncCompleter = Completer<void>()..complete();

  // Public getter to await sync completion
  Future<void> get syncCompleted => _syncCompleter?.future ?? Future.value();

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

  Future<void> _retrySyncForAllServices() async {
    // A sync is starting, create a new, un-completed completer.
    _syncCompleter = Completer<void>();

    try {
      final futures = <Future<void>>[];

      // If no services have been used, there's nothing to sync.
      if (_recordServices.isEmpty) {
        logger.info('No services to sync.');
        _syncCompleter!.complete();
        return;
      }

      for (final service in _recordServices.values) {
        // Convert stream to future and collect all sync operations
        final future = service.retryLocal().last.then((_) {
          logger.fine('Sync completed for service: ${service.service}');
        });
        futures.add(future);
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

  @override
  $CollectionService get collections => $CollectionService(this);

  @override
  $FileService get files => $FileService(this);

  // Clean up resources
  @override
  void close() {
    _connectivitySubscription?.cancel();
    connectivity.dispose();
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
