import 'package:drift/drift.dart';
import 'package:pocketbase/pocketbase.dart';

import 'connection/connection.dart' as impl;
import 'tables.dart';

part 'database.g.dart';

@DriftDatabase(tables: [Records], include: {'sql.drift'})
class PocketBaseDatabase extends _$PocketBaseDatabase {
  PocketBaseDatabase({
    String dbName = 'database.db',
    DatabaseConnection? connection,
    bool useWebWorker = false,
    bool logStatements = false,
  }) : super.connect(
          connection ??
              impl.connect(
                dbName,
                useWebWorker: useWebWorker,
                logStatements: logStatements,
              ),
        );

  @override
  int get schemaVersion => 1;

  Future<int> setRecord(RecordModel item) async {
    final id = await into(records).insert(
      item.toCompanion(),
      mode: InsertMode.insertOrReplace,
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

  Future<RecordModel?> get(int id) async {
    final query = select(records)..where((t) => t.id.equals(id));
    final item = await query.getSingleOrNull();
    return item?.toModel();
  }

  Future<int> set(RecordModel item) {
    return into(records).insert(
      item.toCompanion(),
      mode: InsertMode.insertOrReplace,
    );
  }

  Future<void> remove(int id) async {
    await (delete(records)..where((t) => t.id.equals(id))).go();
  }

  Future<List<RecordModel>> getRecords(String collection) async {
    final items = await getRawRecords(collection);
    return items.map((item) => item.toModel()).toList();
  }

  Future<List<Record>> getRawRecords(String collection) async {
    final query = select(records)
      ..where((t) => t.collectionName.equals(collection));
    final items = await query.get();
    return items;
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

  Stream<List<RecordModel>> watchRecords(String collection) {
    final query = select(records)
      ..where((t) => t.collectionName.equals(collection));
    return query
        .watch()
        .map((rows) => rows.map((row) => row.toModel()).toList());
  }

  Stream<RecordModel?> watchRecord(String collection, String id) {
    final query = select(records)
      ..where((t) => t.rowId.equals(id))
      ..where((t) => t.collectionName.equals(collection));
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
  RecordsCompanion toCompanion([int? currentId]) {
    return RecordsCompanion.insert(
      id: currentId != null ? Value(currentId) : const Value.absent(),
      rowId: id,
      collectionId: collectionId,
      collectionName: collectionName,
      data: toJson(),
      created: created,
      updated: updated,
    );
  }
}

extension on Record {
  RecordModel toModel() {
    return RecordModel(
      id: rowId,
      collectionId: collectionId,
      collectionName: collectionName,
      data: data,
      created: created,
      updated: updated,
    );
  }
}
