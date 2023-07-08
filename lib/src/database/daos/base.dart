import 'package:drift/drift.dart';

import '../database.dart';
import '../tables.dart';

abstract class ServiceRecordsDao<TableDsl extends ServiceRecords,
    T extends ServiceRecord> extends DatabaseAccessor<DataBase> {
  ServiceRecordsDao(DataBase db) : super(db);

  TableInfo<TableDsl, T> get table;

  SimpleSelectStatement<TableDsl, T> target({
    String? id,
    int? page,
    int? perPage,
  }) {
    var query = select(table);
    if (id != null) {
      query = query..where((t) => t.id.equals(id));
    }
    if (page != null && perPage != null) {
      final limit = perPage;
      final offset = (page - 1) * perPage;
      query = query..limit(limit, offset: offset);
    }
    return query;
  }

  Future<List<T>> getAll({
    int? page,
    int? perPage,
  }) {
    return target(
      page: page,
      perPage: perPage,
    ).get();
  }

  Stream<List<T>> watchAll({
    int? page,
    int? perPage,
  }) {
    return target(
      page: page,
      perPage: perPage,
    ).watch();
  }

  Future<T?> get(String id) {
    return target(
      id: id,
    ).getSingleOrNull();
  }

  Stream<T?> watch(String id) {
    return target(
      id: id,
    ).watchSingleOrNull();
  }

  Future<int> getCount() async {
    final count = countAll();
    var q = selectOnly(table)..addColumns([count]);
    return q.map((row) => row.read(count)!).getSingle();
  }

  Future<void> deleteItem(String id) async {
    var query = delete(table);
    query = query..where((t) => t.id.equals(id));
    await query.go();
  }

  Insertable<T> toCompanion(T data);

  Future<String> createItem(T data) async {
    final companion = toCompanion(data);
    final item = await into(table).insertReturning(
      companion,
      mode: InsertMode.insertOrReplace,
    );
    return item.id;
  }

  // Future<void> updateItem(T data) async {
  //   final companion = toCompanion(data);
  //   var query = update(table);
  //   query = query..where((tbl) => tbl.id.equals(data.id));
  //   await query.write(companion);
  // }

  // Future<String> createItem(T data);

  Future<void> updateItem(T data);

  // Future<void> addAll(List<T> items) async {
  //   return transaction(() async {
  //     // TODO: Batch?
  //     for (final item in items) {
  //       var query = select(table);
  //       query = query..where((tbl) => tbl.id.equals(item.id));
  //       final existing = await query.getSingleOrNull();
  //       if (existing != null) {
  //         await updateItem(item);
  //       } else {
  //         await createItem(item);
  //       }
  //     }
  //   });
  // }
}
