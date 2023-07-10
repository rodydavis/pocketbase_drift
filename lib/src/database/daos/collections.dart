import 'package:drift/drift.dart';
import 'package:pocketbase/pocketbase.dart';

import '../database.dart';
import '../tables.dart';
import 'base.dart';

part 'collections.g.dart';

@DriftAccessor(tables: [Collections])
class CollectionsDao extends ServiceRecordsDao<$CollectionsTable, Collection> with _$CollectionsDaoMixin {
  CollectionsDao(DataBase db) : super(db);

  @override
  $CollectionsTable get table => collections;

  @override
  Insertable<Collection> toCompanion(Collection data) {
    return data.toCompanion(true).copyWith(
          id: data.id.isEmpty ? const Value.absent() : Value(data.id),
        );
  }

  @override
  Future<void> updateItem(Collection data) async {
    final companion = toCompanion(data);
    final existing = await (select(table)..where((tbl) => tbl.id.equals(data.id))).getSingleOrNull();
    if (existing == null) {
      await into(table).insert(companion);
    } else {
      await update(table).replace(companion);
    }
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

@DataClassName('Collection', extending: ServiceRecord)
class Collections extends Table with ServiceRecords {
  TextColumn get type => text().withDefault(const Constant('base'))();
  TextColumn get name => text()();
  BoolColumn get system => boolean().withDefault(const Constant(false))();
  TextColumn get listRule => text().nullable()();
  TextColumn get viewRule => text().nullable()();
  TextColumn get createRule => text().nullable()();
  TextColumn get updateRule => text().nullable()();
  TextColumn get deleteRule => text().nullable()();
  TextColumn get schema => text().map(const SchemaFieldListMapper())();
  TextColumn get indexes => text().map(const StringListMapper())();
  TextColumn get options => text().map(const JsonMapper())();

  @override
  Set<Column<Object>>? get primaryKey => {id};
}

extension CollectionModelUtils on CollectionModel {
  Collection toModel({
    required bool? synced,
    required bool? deleted,
    bool? isNew,
    bool? local,
  }) {
    return Collection(
      id: id,
      metadata: {
        'synced': synced,
        'deleted': deleted,
        if (isNew != null) 'new': isNew,
        if (local != null) 'local': local,
      },
      created: DateTime.tryParse(created) ?? DateTime.now(),
      updated: DateTime.tryParse(updated) ?? DateTime.now(),
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
