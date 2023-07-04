// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'records.dart';

// ignore_for_file: type=lint
mixin _$RecordsDaoMixin on DatabaseAccessor<DataBase> {
  $CollectionsTable get collections => attachedDatabase.collections;
  $RecordsTable get records => attachedDatabase.records;
  Future<int> _deleteRecord(String collectionId, String id) {
    return customUpdate(
      'DELETE FROM records WHERE collectionId = ?1 AND id = ?2',
      variables: [Variable<String>(collectionId), Variable<String>(id)],
      updates: {records},
      updateKind: UpdateKind.delete,
    );
  }

  Future<int> _removeSyncedDeletedRecords() {
    return customUpdate(
      'DELETE FROM records WHERE synced = 1 AND deleted = 1',
      variables: [],
      updates: {records},
      updateKind: UpdateKind.delete,
    );
  }

  Selectable<Record> _getPendingWritesRecords() {
    return customSelect(
        'SELECT * FROM records WHERE synced = 0 AND deleted = 0',
        variables: [],
        readsFrom: {
          records,
        }).asyncMap(records.mapFromRow);
  }

  Selectable<Record> _getPendingDeletesRecords() {
    return customSelect(
        'SELECT * FROM records WHERE synced = 0 AND deleted = 1',
        variables: [],
        readsFrom: {
          records,
        }).asyncMap(records.mapFromRow);
  }

  Selectable<Record> _getPendingRecords() {
    return customSelect('SELECT * FROM records WHERE synced = 0',
        variables: [],
        readsFrom: {
          records,
        }).asyncMap(records.mapFromRow);
  }
}
