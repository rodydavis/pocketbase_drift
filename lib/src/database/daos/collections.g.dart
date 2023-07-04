// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'collections.dart';

// ignore_for_file: type=lint
mixin _$CollectionsDaoMixin on DatabaseAccessor<DataBase> {
  $CollectionsTable get collections => attachedDatabase.collections;
  $RecordsTable get records => attachedDatabase.records;
  Selectable<Collection> _allCollections() {
    return customSelect('SELECT * FROM collections', variables: [], readsFrom: {
      collections,
    }).asyncMap(collections.mapFromRow);
  }

  Selectable<Collection> _getCollection(String id) {
    return customSelect('SELECT * FROM collections WHERE id = ?1', variables: [
      Variable<String>(id)
    ], readsFrom: {
      collections,
    }).asyncMap(collections.mapFromRow);
  }

  Selectable<Collection> _getCollectionByName(String name) {
    return customSelect('SELECT * FROM collections WHERE name = ?1',
        variables: [
          Variable<String>(name)
        ],
        readsFrom: {
          collections,
        }).asyncMap(collections.mapFromRow);
  }

  Future<int> _deleteCollection(String id) {
    return customUpdate(
      'DELETE FROM collections WHERE id = ?1',
      variables: [Variable<String>(id)],
      updates: {collections},
      updateKind: UpdateKind.delete,
    );
  }

  Future<int> _deleteRecordsByCollection(String id) {
    return customUpdate(
      'DELETE FROM records WHERE collectionId = ?1',
      variables: [Variable<String>(id)],
      updates: {records},
      updateKind: UpdateKind.delete,
    );
  }

  Selectable<Collection> _getCollectionsPaginated(int limit, int offset) {
    return customSelect('SELECT * FROM collections LIMIT ?1 OFFSET ?2',
        variables: [
          Variable<int>(limit),
          Variable<int>(offset)
        ],
        readsFrom: {
          collections,
        }).asyncMap(collections.mapFromRow);
  }
}
