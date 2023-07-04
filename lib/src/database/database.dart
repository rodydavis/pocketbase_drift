import 'package:drift/drift.dart';
import 'package:pocketbase/pocketbase.dart';

import 'connection/connection.dart' as impl;
import 'daos/records.dart';
import 'daos/collections.dart';
import 'tables.dart';

export 'daos/records.dart';
export 'daos/collections.dart';

part 'database.g.dart';

@DriftDatabase(
  tables: [Records, Collections],
  daos: [RecordsDao, CollectionsDao],
  include: {'sql/search.drift'},
)
class DataBase extends _$DataBase {
  DataBase(DatabaseConnection connection) : super.connect(connection);

  factory DataBase.file({
    String dbName = 'pocketbase.db',
    bool logStatements = false,
  }) {
    return DataBase(impl.connect(
      dbName,
      logStatements: logStatements,
    ));
  }

  @override
  int get schemaVersion => 3;

  Future<List<RecordModel>> search(
    String query, {
    String? collectionId,
  }) async {
    final results = await _search(query).get();
    final items = results.map((e) => e.r.toModel()).toList();
    if (collectionId == null) return items;
    return items.where((item) => item.collectionId == collectionId).toList();
  }

  String generateId() => newId();
}
