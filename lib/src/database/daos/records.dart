import 'package:drift/drift.dart';
import 'package:pocketbase/pocketbase.dart';

import '../database.dart';
import '../tables.dart';

part 'records.g.dart';

@DriftAccessor(
  tables: [Records, Collections],
  include: {'../sql/records.drift'},
)
class RecordsDao extends DatabaseAccessor<DataBase> with _$RecordsDaoMixin {
  RecordsDao(DataBase db) : super(db);

  Future<String> createRecord({
    required Collection collection,
    required Map<String, dynamic> data,
    required String? id,
    bool? synced,
    bool? deleted = false,
  }) async {
    final companion = RecordsCompanion.insert(
      created: DateTime.now(),
      updated: DateTime.now(),
      collectionId: collection.id,
      collectionName: collection.name,
      data: data,
      synced: synced != null ? Value(synced) : const Value.absent(),
      deleted: deleted != null ? Value(deleted) : const Value.absent(),
      id: Value(id ?? db.generateId()),
    );
    final record = await into(records).insertReturning(
      companion,
      mode: InsertMode.insertOrReplace,
    );
    return record.id;
  }

  Future<void> updateRecord({
    required String id,
    required Collection collection,
    required Map<String, dynamic> data,
    bool? synced,
    bool? deleted = false,
  }) async {
    await createRecord(
      id: id,
      collection: collection,
      deleted: deleted,
      synced: synced,
      data: data,
    );
    // final existing = await _get(
    //   collectionId: collection.id,
    //   id: id,
    // ).getSingleOrNull();
    // if (existing == null) {
    //   throw Exception('Record $id not found in ${collection.id}');
    // }
    // final companion = existing.toCompanion(true).copyWith(
    //       updated: Value(DateTime.now()),
    //       data: Value(data),
    //       synced: synced != null ? Value(synced) : const Value.absent(),
    //       deleted: deleted != null ? Value(deleted) : const Value.absent(),
    //     );
    // var query = update(records);
    // query = query..where((t) => t.id.equals(id));
    // query = query..where((t) => t.collectionId.equals(collection.id));

    // await query.write(companion);
  }

  Future<void> deleteRecord({
    required String id,
    required String collectionId,
  }) async {
    await _deleteRecord(
      collectionId,
      id,
    );
  }

  // Future<RecordModel> createRecordModel({
  //   required Collection collection,
  //   required RecordModel item,
  //   bool deleted = false,
  //   bool? synced,
  // }) async {
  //   final id = await createRecord(
  //     collection: collection,
  //     id: item.id,
  //     data: item.data,
  //     synced: synced,
  //     deleted: deleted,
  //   );
  //   final record = await getRecord(
  //     collectionId: collection.id,
  //     id: id,
  //   );
  //   return record!;
  // }

  // Future<RecordModel> updateRecordModel({
  //   required String collectionId,
  //   required RecordModel item,
  //   bool deleted = false,
  //   bool? synced,
  // }) async {
  //   await updateRecord(
  //     id: item.id,
  //     collectionId: collectionId,
  //     data: item.data,
  //     synced: synced,
  //     deleted: deleted,
  //   );
  //   final record = await getRecord(
  //     collectionId: collectionId,
  //     id: item.id,
  //   );
  //   return record!;
  // }

  Future<void> deleteRecordModel({
    required String collectionId,
    required RecordModel item,
  }) async {
    await deleteRecord(
      id: item.id,
      collectionId: collectionId,
    );
  }

  Selectable<Record?> _get({
    required String collectionId,
    required String id,
    bool? deleted = false,
    bool? synced,
  }) {
    var query = select(records)
      ..where((tbl) => tbl.collectionId.equals(collectionId))
      ..where((tbl) => tbl.id.equals(id));
    if (deleted != null) {
      query = query..where((tbl) => tbl.deleted.equals(deleted));
    }
    if (synced != null) {
      query = query..where((tbl) => tbl.synced.equals(synced));
    }
    return query;
  }

  Selectable<Record> _getAll({
    String? collectionId,
    bool? deleted = false,
    bool? synced,
    int? page,
    int? perPage,
  }) {
    var query = select(records);
    if (collectionId != null) {
      query = query..where((tbl) => tbl.collectionId.equals(collectionId));
    }
    if (deleted != null) {
      query = query..where((tbl) => tbl.deleted.equals(deleted));
    }
    if (synced != null) {
      query = query..where((tbl) => tbl.synced.equals(synced));
    }
    if (page != null && perPage != null) {
      final limit = perPage;
      final offset = (page - 1) * perPage;
      query = query..limit(limit, offset: offset);
    }
    return query;
  }

  Future<List<RecordModel>> getAll({
    String? collectionId,
    bool? deleted = false,
    bool? synced,
    int? page,
    int? perPage,
  }) async {
    final records = await _getAll(
      collectionId: collectionId,
      deleted: deleted,
      synced: synced,
      page: page,
      perPage: perPage,
    ).get();
    return records.map((e) => e.toModel()).toList();
  }

  Stream<List<RecordModel>> watchAll({
    String? collectionId,
    bool? deleted = false,
    bool? synced,
    int? page,
    int? perPage,
  }) async* {
    final records = _getAll(
      collectionId: collectionId,
      deleted: deleted,
      synced: synced,
      page: page,
      perPage: perPage,
    ).watch();
    await for (final list in records) {
      yield list.map((e) => e.toModel()).toList();
    }
  }

  Future<RecordModel?> getRecord({
    required String collectionId,
    required String id,
    bool? deleted = false,
    bool? synced,
  }) async {
    final record = await _get(
      collectionId: collectionId,
      id: id,
      deleted: deleted,
      synced: synced,
    ).getSingleOrNull();
    return record?.toModel();
  }

  Stream<RecordModel?> watchRecord({
    required String collectionId,
    required String id,
    bool? deleted = false,
    bool? synced,
  }) async* {
    final record = _get(
      collectionId: collectionId,
      id: id,
      deleted: deleted,
      synced: synced,
    ).watchSingleOrNull();
    await for (final item in record) {
      yield item?.toModel();
    }
  }

  Future<void> removeSyncedDeletedRecords() => _removeSyncedDeletedRecords();

  Future<List<Record>> getPendingWrites() => _getPendingWritesRecords().get();

  Future<List<Record>> getPendingDeletes() => _getPendingDeletesRecords().get();

  Future<List<Record>> getPending() => _getPendingRecords().get();

  Future<void> addAll(
    Collection collection,
    List<RecordModel> items, {
    bool deleted = false,
    bool? synced,
  }) async {
    return transaction(() async {
      // TODO: Batch?
      for (final item in items) {
        await updateRecord(
          collection: collection,
          id: item.id,
          data: item.data,
          synced: synced,
          deleted: deleted,
        );
      }
    });
  }

  Future<int> getRecordCount({
    required String collectionId,
    bool? deleted = false,
    bool? synced,
  }) async {
    var query = select(records)
      ..where((t) => t.collectionId.equals(collectionId));
    if (deleted != null) {
      query = query..where((t) => t.deleted.equals(deleted));
    }
    if (synced != null) {
      query = query..where((t) => t.synced.equals(synced));
    }
    final count = countAll();
    var q = selectOnly<$RecordsTable, Record>(records)
      ..addColumns([count])
      ..where(records.collectionId.equals(collectionId));
    if (deleted != null) {
      q = q..where(records.deleted.equals(deleted));
    }
    if (synced != null) {
      q = q..where(records.synced.equals(synced));
    }
    return q.map((row) => row.read(count)!).getSingle();
  }

  Future<String> getId(int rowId) async {
    final query = select(records)..where((tbl) => tbl.rowId.equals(rowId));
    final result = await query.getSingle();
    return result.id;
  }
}

extension RecordUtils on Record {
  RecordModel toModel() {
    return RecordModel(
      id: id,
      collectionId: collectionId,
      collectionName: collectionName,
      data: data,
      created: created.toIso8601String(),
      updated: created.toIso8601String(),
    );
  }
}

extension RecordModelUtils on RecordModel {
  Record toModel({bool? synced, bool? deleted}) => Record(
        id: id,
        collectionId: collectionId,
        collectionName: collectionName,
        data: data,
        created: DateTime.parse(created),
        updated: DateTime.parse(updated),
        synced: synced,
        deleted: deleted,
      );
}
