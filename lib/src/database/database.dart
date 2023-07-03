import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:pocketbase/pocketbase.dart';

import 'connection/connection.dart' as impl;
import 'tables.dart';

part 'database.g.dart';

@DriftDatabase(tables: [Records], include: {'sql.drift'})
class DataBase extends _$DataBase {
  DataBase(DatabaseConnection connection) : super.connect(connection);

  factory DataBase.file({
    String dbName = 'pocketbase.db',
    bool useWebWorker = false,
    bool logStatements = false,
  }) {
    return DataBase(impl.connect(
      dbName,
      useWebWorker: useWebWorker,
      logStatements: logStatements,
    ));
  }

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        await m.createAll();
      },
      onUpgrade: (Migrator m, int from, int to) async {
        if (from < 2) {
          await m.addColumn(records, records.synced);
        }
        return;
      },
    );
  }

  Future<int> setRecord(
    RecordModel item, {
    bool synced = false,
    bool deleted = false,
  }) async {
    final id = await into(records).insert(
      item.toCompanion(
        isDeleted: deleted,
        isSynced: synced,
      ),
      mode: InsertMode.insertOrReplace,
    );
    return id;
  }

  Future<int> addRecord(
    RecordModel item, {
    bool synced = false,
    bool deleted = false,
  }) async {
    final id = await into(records).insert(
      item.toCompanion(
        isDeleted: deleted,
        isSynced: synced,
      ),
      mode: InsertMode.insert,
    );
    return id;
  }

  Future<void> setRecords(List<RecordModel> items) {
    return transaction(
      () => batch((batch) {
        final values = items.map((item) => item.toCompanion()).toList();
        batch.insertAll(records, values, mode: InsertMode.insertOrReplace);
      }),
    );
  }

  Future<RecordModel?> getRecord(String collection, String id) async {
    final item = await getRawRecord(collection, id);
    if (item != null) return item.toModel();
    return null;
  }

  Future<Record?> getRawRecord(String collection, String id) async {
    final query = select(records)
      ..where((t) => t.rowId.equals(id))
      ..where((t) => t.collectionName.equals(collection));
    final item = await query.getSingleOrNull();
    return item;
  }

  @visibleForTesting
  Future<RecordModel?> get(int id) async {
    final query = select(records)..where((t) => t.id.equals(id));
    final item = await query.getSingleOrNull();
    return item?.toModel();
  }

  @visibleForTesting
  Future<int> set(
    RecordModel item, {
    bool synced = false,
    bool deleted = false,
  }) {
    return into(records).insert(
      item.toCompanion(
        isDeleted: deleted,
        isSynced: synced,
      ),
      mode: InsertMode.insertOrReplace,
    );
  }

  @visibleForTesting
  Future<void> remove(int id) async {
    await (delete(records)..where((t) => t.id.equals(id))).go();
  }

  Future<List<RecordModel>> getRecords(
    String collection, {
    int? page,
    int? perPage,
    bool? deleted,
    bool? synced,
  }) async {
    var query = select(records)
      ..where((t) => t.collectionName.equals(collection));
    if (deleted != null) {
      query = query..where((t) => t.deleted.equals(deleted));
    }
    if (synced != null) {
      query = query..where((t) => t.synced.equals(synced));
    }
    if (page != null && perPage != null) {
      final offset = page * perPage;
      query = query..limit(perPage, offset: offset);
    }
    final items = await query.get();
    return items.map((item) => item.toModel()).toList();
  }

  Future<int> getRecordCount(
    String collection, {
    bool? deleted,
    bool? synced,
  }) async {
    var query = select(records)
      ..where((t) => t.collectionName.equals(collection));
    if (deleted != null) {
      query = query..where((t) => t.deleted.equals(deleted));
    }
    if (synced != null) {
      query = query..where((t) => t.synced.equals(synced));
    }
    final count = countAll();
    var q = selectOnly<$RecordsTable, Record>(records)
      ..addColumns([count])
      ..where(records.collectionName.equals(collection));
    if (deleted != null) {
      q = q..where(records.deleted.equals(deleted));
    }
    if (synced != null) {
      q = q..where(records.synced.equals(synced));
    }
    return q.map((row) => row.read(count)!).getSingle();
  }

  /// Delete a single record for a given collection and id
  Future<void> deleteRecord(String collection, String id) async {
    final query = delete(records)
      ..where((t) => t.rowId.equals(id))
      ..where((t) => t.collectionName.equals(collection));
    await query.go();
  }

  /// Deletes all records for a collection
  Future<void> deleteRecords(String collection) async {
    final query = delete(records)
      ..where((t) => t.collectionName.equals(collection));
    await query.go();
  }

  Stream<List<RecordModel>> watchRecords(
    String collection, {
    bool? deleted,
    bool? synced,
  }) {
    var query = select(records)
      ..where((t) => t.collectionName.equals(collection));
    if (deleted != null) {
      query = query..where((t) => t.deleted.equals(deleted));
    }
    if (synced != null) {
      query = query..where((t) => t.synced.equals(synced));
    }
    return query
        .watch()
        .map((rows) => rows.map((row) => row.toModel()).toList());
  }

  Stream<RecordModel?> watchRecord(
    String collection,
    String id, {
    bool? deleted,
    bool? synced,
  }) {
    var query = select(records)
      ..where((t) => t.rowId.equals(id))
      ..where((t) => t.collectionName.equals(collection));
    if (deleted != null) {
      query = query..where((t) => t.deleted.equals(deleted));
    }
    if (synced != null) {
      query = query..where((t) => t.synced.equals(synced));
    }
    return query.watchSingleOrNull().map((row) {
      if (row != null) return row.toModel();
      return null;
    });
  }

  Future<List<RecordModel>> searchAll(String query) async {
    final results = await _search(query).get();
    return results.fold<List<RecordModel>>(<RecordModel>[], (prev, item) {
      prev.add(item.r.toModel());
      return prev;
    });
  }

  Future<List<RecordModel>> searchCollection(
    String query,
    String collection,
  ) async {
    final results = await searchAll(query);
    return results.where((item) => item.collectionName == collection).toList();
  }
}

extension on RecordModel {
  RecordsCompanion toCompanion({
    int? currentId,
    bool isDeleted = false,
    bool isSynced = false,
  }) {
    return RecordsCompanion.insert(
      id: currentId != null ? Value(currentId) : const Value.absent(),
      rowId: id,
      collectionId: collectionId,
      collectionName: collectionName,
      data: toJson(),
      created: DateTime.parse(created),
      updated: DateTime.parse(updated),
      synced: Value(isSynced),
      deleted: Value(isDeleted),
    );
  }
}

extension RecordUtils on Record {
  RecordModel toModel() {
    return RecordModel(
      id: rowId,
      collectionId: collectionId,
      collectionName: collectionName,
      data: data,
      created: created.toIso8601String(),
      updated: updated.toIso8601String(),
    );
  }
}
