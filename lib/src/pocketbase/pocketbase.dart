import 'package:drift/drift.dart';
import 'package:http/http.dart';
import 'package:pocketbase/pocketbase.dart';

import '../database/database.dart';
import 'services/collection.dart';
import 'services/record.dart';

class $PocketBase extends PocketBase {
  $PocketBase(
    super.baseUrl, {
    required DatabaseConnection connection,
    super.lang,
    super.authStore,
    Client Function()? httpClientFactory,
  })  : db = DataBase(connection),
        super(httpClientFactory: httpClientFactory);

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
  $CollectionService get collections => $CollectionService(this);

  // TODO: getFileUrl get local url?

  // TODO: Auth servoce
}
