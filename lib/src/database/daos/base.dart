import 'package:drift/drift.dart';

import '../database.dart';
import '../tables.dart';

abstract class ServiceRecordsDao<TableDsl extends ServiceRecords,
    T extends ServiceRecord> extends DatabaseAccessor<DataBase> {
  ServiceRecordsDao(DataBase db) : super(db);

  TableInfo<TableDsl, T> get table;

  SimpleSelectStatement<TableDsl, T> target({
    String? id,
    bool? deleted,
    bool? synced,
    int? page,
    int? perPage,
  }) {
    var query = select(table);
    if (id != null) {
      query = query..where((t) => t.id.equals(id));
    }
    if (deleted != null) {
      query = query..where((t) => t.deleted.equals(deleted));
    }
    if (synced != null) {
      query = query..where((t) => t.synced.equals(synced));
    }
    if (page != null && perPage != null) {
      final limit = perPage;
      final offset = (page - 1) * perPage;
      query = query..limit(limit, offset: offset);
    }
    return query;
  }

  Future<List<T>> getAll({
    bool? deleted,
    bool? synced,
    int? page,
    int? perPage,
  }) {
    return target(
      deleted: deleted,
      synced: synced,
      page: page,
      perPage: perPage,
    ).get();
  }

  Stream<List<T>> watchAll({
    bool? deleted,
    bool? synced,
    int? page,
    int? perPage,
  }) {
    return target(
      deleted: deleted,
      synced: synced,
      page: page,
      perPage: perPage,
    ).watch();
  }

  Future<T?> get(String id, {bool? deleted, bool? synced}) {
    return target(id: id, deleted: deleted, synced: synced).getSingleOrNull();
  }

  Stream<T?> watch(String id, {bool? deleted, bool? synced}) {
    return target(id: id, deleted: deleted, synced: synced).watchSingleOrNull();
  }

  Future<int> getCount({
    bool? deleted,
    bool? synced,
  }) async {
    if (deleted != null || synced != null) {
      var query = select(table);
      if (deleted != null) {
        query = query..where((t) => t.deleted.equals(deleted));
      }
      if (synced != null) {
        query = query..where((t) => t.synced.equals(synced));
      }
      final items = await query.get();
      return items.length;
    }

    final count = countAll();
    var q = selectOnly(table)..addColumns([count]);
    return q.map((row) => row.read(count)!).getSingle();
  }

  Future<void> deleteItem(String id) async {
    var query = delete(table);
    query = query..where((t) => t.id.equals(id));
    await query.go();
  }

  Insertable<T> toCompanion(
    T data, {
    bool? synced,
    bool? deleted,
  });

  Future<String> createItem(
    T data, {
    bool? synced,
    bool? deleted,
  }) async {
    final companion = toCompanion(
      data,
      synced: synced,
      deleted: deleted,
    );
    final item = await into(table).insertReturning(
      companion,
      mode: InsertMode.insertOrReplace,
    );
    return item.id;
  }

  Future<void> updateItem(
    T data, {
    bool? synced,
    bool? deleted,
  }) async {
    final companion = toCompanion(
      data,
      synced: synced,
      deleted: deleted,
    );
    var query = update(table);
    query = query..where((tbl) => tbl.id.equals(data.id));
    await query.write(companion);
  }

  Future<void> addAll(List<T> items) async {
    return transaction(() async {
      // TODO: Batch?
      for (final item in items) {
        var query = select(table);
        query = query..where((tbl) => tbl.id.equals(item.id));
        final existing = await query.getSingleOrNull();
        if (existing != null) {
          await updateItem(item);
        } else {
          await createItem(item);
        }
      }
    });
  }
}
