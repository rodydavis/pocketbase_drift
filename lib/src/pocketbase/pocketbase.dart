import 'package:drift/drift.dart';
import 'package:pocketbase/pocketbase.dart';

import '../database/database.dart';
import 'services/record.dart';

class $PocketBase extends PocketBase {
  $PocketBase(
    super.baseUrl, {
    required DatabaseConnection connection,
    super.lang,
    super.authStore,
    super.httpClientFactory,
  }) : db = DataBase(connection);

  final DataBase db;

  final _recordServices = <String, $RecordService>{};

  $RecordService $collection({
    required String collectionId,
    required String collectionName,
    required IdGenerator idGenerator,
  }) {
    var service = _recordServices[collectionId];

    if (service == null) {
      service = $RecordService(
        this,
        collectionId: collectionId,
        collectionName: collectionName,
        idGenerator: idGenerator,
      );
      _recordServices[collectionId] = service;
    }

    return service;
  }

  // TODO: getFileUrl get local url?

  // TODO: Auth servoce
}
