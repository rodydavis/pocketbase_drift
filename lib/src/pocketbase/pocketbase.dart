import 'package:drift/drift.dart';
import 'package:http/http.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:shortid/shortid.dart';

import '../network/http.dart';
import '../database/database.dart';
import 'services/record.dart';

class $PocketBase extends PocketBase {
  $PocketBase(
    super.baseUrl, {
    required DatabaseConnection connection,
    super.lang,
    super.authStore,
    Client Function()? httpClientFactory,
  })  : db = DataBase(connection),
        super(httpClientFactory: httpClientFactory ?? createHttpClient);

  final DataBase db;
  bool logging = false;

  late IdGenerator idGenerator = () {
    const chars =
        '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
    shortid.characters(chars);
    return shortid.generate().padLeft(15, '0');
  };

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
    return db.searchAll(query);
  }

  // TODO: getFileUrl get local url?

  // TODO: Auth servoce
}
