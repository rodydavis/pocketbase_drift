import 'package:drift/drift.dart';
import 'package:pocketbase/pocketbase.dart';

import '../database.dart';
import '../tables.dart';

part 'collections.g.dart';

@DriftAccessor(
  tables: [Records, Collections],
  include: {'../sql/collections.drift'},
)
class CollectionsDao extends DatabaseAccessor<DataBase>
    with _$CollectionsDaoMixin {
  CollectionsDao(DataBase db) : super(db);

  Future<String> createCollection({
    String? id,
    String? type,
    required String name,
    bool? system,
    String? listRule,
    String? viewRule,
    String? createRule,
    String? updateRule,
    String? deleteRule,
    List<SchemaField> schema = const [],
    List<String> indexes = const [],
    Map<String, dynamic> options = const {},
  }) async {
    final companion = CollectionsCompanion.insert(
      id: Value(id ?? db.generateId()),
      created: DateTime.now(),
      updated: DateTime.now(),
      name: name,
      schema: schema,
      indexes: indexes,
      options: options,
      listRule: listRule != null ? Value(listRule) : const Value.absent(),
      viewRule: viewRule != null ? Value(viewRule) : const Value.absent(),
      createRule: createRule != null ? Value(createRule) : const Value.absent(),
      updateRule: updateRule != null ? Value(updateRule) : const Value.absent(),
      deleteRule: deleteRule != null ? Value(deleteRule) : const Value.absent(),
      system: system != null ? Value(system) : const Value.absent(),
      type: type != null ? Value(type) : const Value.absent(),
    );
    final item = await into(collections).insertReturning(
      companion,
      mode: InsertMode.insertOrReplace,
    );
    return item.id;
  }

  Future<void> updateCollection({
    required String id,
    required String name,
    String? type,
    bool? system,
    String? listRule,
    String? viewRule,
    String? createRule,
    String? updateRule,
    String? deleteRule,
    List<SchemaField> schema = const [],
    List<String> indexes = const [],
    Map<String, dynamic> options = const {},
  }) async {
    await (update(collections)..where((tbl) => tbl.id.equals(id))).write(
      CollectionsCompanion(
        updated: Value(DateTime.now()),
        name: Value(name),
        schema: Value(schema),
        indexes: Value(indexes),
        options: Value(options),
        listRule: listRule != null ? Value(listRule) : const Value.absent(),
        viewRule: viewRule != null ? Value(viewRule) : const Value.absent(),
        createRule:
            createRule != null ? Value(createRule) : const Value.absent(),
        updateRule:
            updateRule != null ? Value(updateRule) : const Value.absent(),
        deleteRule:
            deleteRule != null ? Value(deleteRule) : const Value.absent(),
        system: system != null ? Value(system) : const Value.absent(),
        type: type != null ? Value(type) : const Value.absent(),
      ),
    );
  }

  Future<void> deleteCollection({
    required String id,
  }) async {
    await _deleteCollection(
      id,
    );
  }

  Selectable<Collection> _get({
    int? page,
    int? perPage,
  }) {
    if (page != null && perPage != null) {
      final limit = perPage;
      final offset = (page - 1) * perPage;
      return _getCollectionsPaginated(limit, offset);
    } else {
      return _allCollections();
    }
  }

  Future<List<CollectionModel>> getAll({
    int? page,
    int? perPage,
  }) async {
    final items = await _get(page: page, perPage: perPage).get();
    return items.map((e) => e.toModel()).toList();
  }

  Stream<List<CollectionModel>> watchAll({
    int? page,
    int? perPage,
  }) async* {
    final records = _get(page: page, perPage: perPage).watch();
    await for (final list in records) {
      yield list.map((e) => e.toModel()).toList();
    }
  }

  Future<void> addAll(List<CollectionModel> items) async {
    return transaction(() async {
      // TODO: Batch?
      for (final item in items) {
        final existing = await (select(collections)
              ..where((tbl) => tbl.id.equals(item.id)))
            .getSingleOrNull();
        if (existing != null) {
          await updateCollection(
            id: item.id,
            type: item.type,
            name: item.name,
            system: item.system,
            listRule: item.listRule ?? '',
            viewRule: item.viewRule ?? '',
            createRule: item.createRule ?? '',
            updateRule: item.updateRule ?? '',
            deleteRule: item.deleteRule ?? '',
            schema: item.schema,
            indexes: item.indexes,
            options: item.options,
          );
        } else {
          await createCollection(
            type: item.type,
            name: item.name,
            system: item.system,
            listRule: item.listRule ?? '',
            viewRule: item.viewRule ?? '',
            createRule: item.createRule ?? '',
            updateRule: item.updateRule ?? '',
            deleteRule: item.deleteRule ?? '',
            schema: item.schema,
            indexes: item.indexes,
            options: item.options,
          );
        }
      }
    });
  }

  Future<Collection?> getCollectionById(String id) {
    return _getCollection(id).getSingleOrNull();
  }

  Future<Collection?> getCollectionByName(String name) {
    return _getCollectionByName(name).getSingleOrNull();
  }

  Stream<Collection?> watchCollectionById(String id) {
    return _getCollection(id).watchSingleOrNull();
  }

  Stream<Collection?> watchCollectionByName(String name) {
    return _getCollectionByName(name).watchSingleOrNull();
  }

  Future<String> getId(int rowId) async {
    final query = select(collections)..where((tbl) => tbl.rowId.equals(rowId));
    final result = await query.getSingle();
    return result.id;
  }
}

extension CollectionUtils on Collection {
  CollectionModel toModel() {
    return CollectionModel(
      id: id,
      created: created.toIso8601String(),
      updated: updated.toIso8601String(),
      name: name,
      schema: schema,
      indexes: indexes,
      options: options,
      listRule: listRule,
      viewRule: viewRule,
      createRule: createRule,
      updateRule: updateRule,
      deleteRule: deleteRule,
      system: system,
      type: type,
    );
  }
}

extension CollectionModelUtils on CollectionModel {
  Collection toModel() {
    return Collection(
      id: id,
      created: DateTime.parse(created),
      updated: DateTime.parse(updated),
      name: name,
      schema: schema,
      indexes: indexes,
      options: options,
      listRule: listRule,
      viewRule: viewRule,
      createRule: createRule,
      updateRule: updateRule,
      deleteRule: deleteRule,
      system: system,
      type: type,
    );
  }
}
