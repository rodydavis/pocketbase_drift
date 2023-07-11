// ignore_for_file: overridden_fields

import 'package:drift/drift.dart';
import 'package:http/http.dart';
import 'package:pocketbase/pocketbase.dart';

import '../database/connection/connection.dart';
import '../database/database.dart';
import 'services/admin.dart';
import 'services/backup.dart';
import 'services/collections.dart';
import 'services/files.dart';
import 'services/health.dart';
import 'services/logs.dart';
import 'services/realtime.dart';
import 'services/records.dart';
import 'services/settings.dart';
import 'stores/auth.dart';

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
    DatabaseConnection? connection,
    bool inMemory = false,
    bool autoLoad = true,
    String lang = "en-US",
    Client Function()? httpClientFactory,
  }) {
    final conn = connection ?? connect('app.db', inMemory: inMemory);
    final db = DataBase(conn);
    final authStore = $AuthStore(db, autoLoad: autoLoad);
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

  final _recordServices = <String, $RecordsService>{};

  @override
  $RecordsService collection(String collectionIdOrName) {
    var service = _recordServices[collectionIdOrName];

    if (service == null) {
      service = $RecordsService(this, collectionIdOrName);
      _recordServices[collectionIdOrName] = service;
    }

    return service;
  }

  Selectable<SearchResult> search(String query) => db.search(query);

  @override
  late final $CollectionsService collections = $CollectionsService(this);

  @override
  late final $AdminService admins = $AdminService(this);

  @override
  late final $FileService files = $FileService(this);

  @override
  late final $RealtimeService realtime = $RealtimeService(this);

  @override
  late final $SettingsService settings = $SettingsService(this);

  @override
  late final $LogService logs = $LogService(this);

  @override
  late final $HealthService health = $HealthService(this);

  @override
  late final $BackupService backups = $BackupService(this);
}
