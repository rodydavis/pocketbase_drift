// ignore_for_file: overridden_fields

import 'package:drift/drift.dart';
import 'package:http/http.dart';
import 'package:pocketbase/pocketbase.dart';

import '../database/connection/connection.dart';
import '../database/database.dart';
import 'services/admin.dart';
import 'services/backup.dart';
import 'services/collection.dart';
import 'services/files.dart';
import 'services/health.dart';
import 'services/logs.dart';
import 'services/realtime.dart';
import 'services/record.dart';
import 'services/settings.dart';
import 'stores/auth.dart';

class $PocketBase extends PocketBase {
  $PocketBase(
    super.baseUrl, {
    super.lang,
    super.authStore,
    required DataBase database,
    bool inMemory = false,
    Client Function()? httpClientFactory,
  })  : db = database,
        super(httpClientFactory: httpClientFactory);

  factory $PocketBase.database(
    String baseUrl, {
    DatabaseConnection? connection,
    bool inMemory = false,
    String lang = "en-US",
    Client Function()? httpClientFactory,
  }) {
    final db = DataBase(
      connection ?? connect('app.db', inMemory: inMemory),
    );
    final authStore = $AuthStore(db);
    return $PocketBase(
      baseUrl,
      database: db,
      lang: lang,
      authStore: authStore,
      httpClientFactory: httpClientFactory,
    );
  }

  final DataBase db;
  bool logging = false;

  final _recordServices = <String, $RecordService>{};

  $RecordService $collection(CollectionModel collection) {
    var service = _recordServices[collection.id];

    if (service == null) {
      service = $RecordService(this, collection);
      _recordServices[collection.id] = service;
    }

    return service;
  }

  Future<List<RecordModel>> search(String query) {
    return db.search(query);
  }

  @override
  late final $CollectionService collections = $CollectionService(this);

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
