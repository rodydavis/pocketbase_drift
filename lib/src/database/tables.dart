import 'dart:convert';

import 'package:drift/drift.dart';

@DataClassName('Record')
class Records extends Table with AutoIncrementingPrimaryKey {
  TextColumn get rowId => text()();
  TextColumn get collectionId => text()();
  TextColumn get collectionName => text()();
  TextColumn get data => text().map(const JsonMapper())();
  BoolColumn get synced => boolean().nullable()();
  BoolColumn get deleted => boolean().nullable()();
  DateTimeColumn get created => dateTime()();
  DateTimeColumn get updated => dateTime()();

  @override
  List<Set<Column<Object>>>? get uniqueKeys => [
        {collectionId, rowId}
      ];
}

mixin AutoIncrementingPrimaryKey on Table {
  IntColumn get id => integer().autoIncrement()();
}

class JsonMapper extends TypeConverter<Map<String, dynamic>, String> {
  const JsonMapper();

  @override
  Map<String, dynamic> fromSql(String fromDb) => jsonDecode(fromDb);

  @override
  String toSql(Map<String, dynamic> value) => jsonEncode(value);
}
