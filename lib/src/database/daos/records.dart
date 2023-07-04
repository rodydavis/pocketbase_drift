import 'package:drift/drift.dart';
import 'package:pocketbase/pocketbase.dart';

import '../database.dart';
import '../tables.dart';
import 'base.dart';

part 'records.g.dart';

@DriftAccessor(
  tables: [Records, Collections],
  include: {'../sql/records.drift'},
)
class RecordsDao extends ServiceRecordsDao<$RecordsTable, Record>
    with _$RecordsDaoMixin {
  RecordsDao(DataBase db) : super(db);

  @override
  $RecordsTable get table => records;

  Future<void> removeSyncedDeletedRecords() => _removeSyncedDeletedRecords();

  Future<List<Record>> getPendingWrites() => _getPendingWritesRecords().get();

  Future<List<Record>> getPendingDeletes() => _getPendingDeletesRecords().get();

  Future<List<Record>> getPending() => _getPendingRecords().get();

  @override
  SimpleSelectStatement<$RecordsTable, Record> target({
    String? id,
    bool? deleted,
    bool? synced,
    int? page,
    int? perPage,
    String? collection,
  }) {
    var query = super.target(
      id: id,
      deleted: deleted,
      synced: synced,
      page: page,
      perPage: perPage,
    );
    if (collection != null) {
      query = query..where((t) => t.collectionId.equals(collection));
    }
    return query;
  }

  @override
  Future<List<Record>> getAll({
    bool? deleted,
    bool? synced,
    int? page,
    int? perPage,
    String? collection,
  }) {
    return target(
      deleted: deleted,
      synced: synced,
      page: page,
      perPage: perPage,
      collection: collection,
    ).get();
  }

  @override
  Stream<List<Record>> watchAll({
    bool? deleted,
    bool? synced,
    int? page,
    int? perPage,
    String? collection,
  }) {
    return target(
      deleted: deleted,
      synced: synced,
      page: page,
      perPage: perPage,
      collection: collection,
    ).watch();
  }

  @override
  Future<Record?> get(
    String id, {
    bool? deleted,
    bool? synced,
    String? collection,
  }) {
    return target(
      id: id,
      deleted: deleted,
      synced: synced,
      collection: collection,
    ).getSingleOrNull();
  }

  @override
  Stream<Record?> watch(
    String id, {
    bool? deleted,
    bool? synced,
    String? collection,
  }) {
    return target(
      id: id,
      deleted: deleted,
      synced: synced,
      collection: collection,
    ).watchSingleOrNull();
  }

  @override
  Insertable<Record> toCompanion(
    Record data, {
    bool? synced,
    bool? deleted,
  }) {
    return data.toCompanion(true).copyWith(
          synced: synced == null ? const Value.absent() : Value(synced),
          deleted: deleted == null ? const Value.absent() : Value(deleted),
          id: data.id.isEmpty ? const Value.absent() : Value(data.id),
        );
  }

  @override
  Future<int> getCount({
    bool? deleted,
    bool? synced,
    String? collection,
  }) async {
    if (collection != null) {
      final items = await getAll(
        deleted: deleted,
        synced: synced,
        collection: collection,
      );
      return items.length;
    }
    return super.getCount(
      deleted: deleted,
      synced: synced,
    );
  }

  @override
  Future<void> deleteItem(
    String id, {
    String? collection,
  }) async {
    if (collection != null) {
      var query = delete(table);
      query = query..where((t) => t.id.equals(id));
      query = query..where((t) => t.collectionId.equals(collection));
      await query.go();
      return;
    }
    return super.deleteItem(id);
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
        created: DateTime.tryParse(created) ?? DateTime.now(),
        updated: DateTime.tryParse(updated) ?? DateTime.now(),
        synced: synced,
        deleted: deleted,
      );
}
