import 'package:drift/drift.dart';
import 'package:pocketbase/pocketbase.dart';

import '../database.dart';
import '../tables.dart';
import 'base.dart';

part 'collections.g.dart';

@DriftAccessor(tables: [Collections])
class CollectionsDao extends ServiceRecordsDao<$CollectionsTable, Collection>
    with _$CollectionsDaoMixin {
  CollectionsDao(DataBase db) : super(db);

  @override
  $CollectionsTable get table => collections;

  @override
  Insertable<Collection> toCompanion(
    Collection data, {
    bool? synced,
    bool? deleted,
  }) {
    return data.toCompanion(true).copyWith(
          synced: synced == null ? const Value.absent() : Value(synced),
          deleted: deleted == null ? const Value.absent() : Value(deleted),
          id: data.id.isEmpty ? const Value.absent() : Value(data.id),
        );
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
