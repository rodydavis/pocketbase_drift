// ignore_for_file: overridden_fields

import 'package:drift/drift.dart';
import 'package:http/http.dart';
import 'package:pocketbase_drift/pocketbase_drift.dart';
import 'package:shared_preferences/shared_preferences.dart';


class $PocketBase extends PocketBase {
  $PocketBase(
    super.baseUrl, {
    super.lang,
    required this.authStore,
    required DataBase database,
    Client Function()? httpClientFactory,
  })  : db = database,
        super(httpClientFactory: httpClientFactory);

  factory $PocketBase.database(
    String baseUrl, {
    required DatabaseConnection connection,
    required SharedPreferences prefs,
    bool inMemory = false,
    bool autoLoad = true,
    String lang = "en-US",
    Client Function()? httpClientFactory,
  }) {
    final db = DataBase(connection);
    final authStore = $AuthStore(prefs);
    return $PocketBase(
      baseUrl,
      database: db,
      lang: lang,
      authStore: authStore,
      httpClientFactory: httpClientFactory,
    );
  }

  @override
  final $AuthStore authStore;

  final DataBase db;
  bool logging = false;

  final _recordServices = <String, $RecordService>{};

  @override
  $RecordService collection(String collectionIdOrName) {
    var service = _recordServices[collectionIdOrName];

    if (service == null) {
      service = $RecordService(this, collectionIdOrName);
      _recordServices[collectionIdOrName] = service;
      service.retryLocal();
    }

    return service;
  }

  /// Get a collection by id or name and fetch
  /// the scheme to set it locally for use in
  /// validation and relations
  Future<$RecordService> $collection(
    String collectionIdOrName, {
    FetchPolicy fetchPolicy = FetchPolicy.cacheAndNetwork,
  }) async {
    await collections.getFirstListItem(
      'id = "$collectionIdOrName" || name = "$collectionIdOrName"',
      fetchPolicy: fetchPolicy,
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

  // @override
  // $AdminsService get admins => $AdminsService(this);

  // @override
  // $FileService get files => $FileService(this);

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
