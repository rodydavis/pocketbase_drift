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

  Future<void> removeSyncedDeletedRecords({String? collection}) async {
    final deletes = await getPendingDeletes();
    for (final item in deletes) {
      await deleteItem(item.id, collection: collection);
    }
  }

  Future<List<Record>> getPendingWrites({String? collection}) async {
    final records = await getAll(collection: collection);
    return records.where((e) {
      final deleted = e.metadata['deleted'] == false;
      final synced = e.metadata['synced'] == false;
      return deleted && synced;
    }).toList();
  }

  Future<List<Record>> getPendingDeletes({String? collection}) async {
    final records = await getAll(collection: collection);
    return records.where((e) {
      final deleted = e.metadata['deleted'] == true;
      final synced = e.metadata['synced'] == false;
      return deleted && synced;
    }).toList();
  }

  Future<List<Record>> getPending({String? collection}) async {
    final records = await getAll(collection: collection);
    return records.where((e) {
      final synced = e.metadata['synced'] == false;
      return synced;
    }).toList();
  }

  @override
  SimpleSelectStatement<$RecordsTable, Record> target({
    String? id,
    int? page,
    int? perPage,
    String? collection,
  }) {
    var query = super.target(
      id: id,
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
    int? page,
    int? perPage,
    String? collection,
  }) {
    return target(
      page: page,
      perPage: perPage,
      collection: collection,
    ).get();
  }

  @override
  Stream<List<Record>> watchAll({
    int? page,
    int? perPage,
    String? collection,
  }) {
    return target(
      page: page,
      perPage: perPage,
      collection: collection,
    ).watch();
  }

  @override
  Future<Record?> get(
    String id, {
    String? collection,
  }) {
    return target(
      id: id,
      collection: collection,
    ).getSingleOrNull();
  }

  @override
  Stream<Record?> watch(
    String id, {
    String? collection,
  }) {
    return target(
      id: id,
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
          id: data.id.isEmpty ? const Value.absent() : Value(data.id),
        );
  }

  @override
  Future<int> getCount({
    String? collection,
  }) async {
    if (collection != null) {
      final items = await getAll(
        collection: collection,
      );
      return items.length;
    }
    return super.getCount();
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

  @override
  Future<void> updateItem(Record data) async {
    await into(table).insert(
      data,
      mode: InsertMode.insertOrReplace,
    );
  }

  Future<void> batchAdd(List<Record> items) async {
    await batch((batch) {
      for (final item in items) {
        batch.insert(
          table,
          item.toCompanion(true),
          mode: InsertMode.insertOrReplace,
        );
      }
    });
  }

  Future<void> batchRemove({
    String? collection,
    List<Record>? items,
  }) async {
    await batch((batch) {
      if (items != null) {
        for (final item in items) {
          batch.delete(table, item.toCompanion(true));
        }
      } else if (collection != null) {
        batch.deleteWhere(table, (e) => e.collectionId.equals(collection));
      } else {
        batch.deleteAll(table);
      }
    });
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

@DataClassName('Record', extending: ServiceRecord)
class Records extends Table with ServiceRecords {
  TextColumn get data => text().map(const JsonMapper())();
  TextColumn get collectionId => text().references(Collections, #id)();
  TextColumn get collectionName => text().references(Collections, #name)();

  @override
  Set<Column<Object>>? get primaryKey => {id, collectionId};
}

extension RecordModelUtils on RecordModel {
  Record toModel({
    required bool? synced,
    required bool? deleted,
    bool? isNew,
    bool? local,
  }) =>
      Record(
        id: id,
        metadata: {
          'synced': synced,
          'deleted': deleted,
          if (isNew != null) 'new': isNew,
          if (local != null) 'local': local,
        },
        created: DateTime.tryParse(created) ?? DateTime.now(),
        updated: DateTime.tryParse(updated) ?? DateTime.now(),
        collectionId: collectionId,
        collectionName: collectionName,
        data: data,
      );
}
