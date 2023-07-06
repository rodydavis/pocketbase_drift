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
}
