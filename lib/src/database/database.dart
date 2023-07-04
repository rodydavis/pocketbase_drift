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
  // include: {'sql/search.drift'},
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

  // @override
  // MigrationStrategy get migration {
  //   return MigrationStrategy(
  //     beforeOpen: (details) async {
  //       if (details.wasCreated) {}
  //       // await customStatement('PRAGMA foreign_keys = ON');
  //     },
  //     onCreate: (Migrator m) async {
  //       await m.createAll();
  //     },
  //     onUpgrade: (Migrator m, int from, int to) async {
  //       // if (from < 2) {
  //       //   await m.addColumn(records, records.synced);
  //       // }
  //       return;
  //     },
  //   );
  // }

  Future<List<RecordModel>> search(
    String query, {
    String? collectionId,
  }) async {
    // final results = await _search(query).get();
    // final items = results.map((e) => e.r.toModel()).toList();
    // if (collectionId == null) return items;
    // return items.where((item) => item.collectionId == collectionId).toList();
    return [];
  }

  String generateId() => newId();
}
