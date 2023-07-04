import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:shortid/shortid.dart';

@DataClassName('Record')
class Records extends Table {
  TextColumn get id => text().clientDefault(newId)();
  TextColumn get data => text().map(const JsonMapper())();
  TextColumn get collectionId => text().references(Collections, #id)();
  TextColumn get collectionName => text().references(Collections, #name)();
  BoolColumn get synced => boolean().nullable()();
  BoolColumn get deleted => boolean().nullable()();
  DateTimeColumn get created => dateTime()();
  DateTimeColumn get updated => dateTime()();

  @override
  Set<Column<Object>>? get primaryKey => {id, collectionId};
}

@DataClassName('Collection')
class Collections extends Table {
  TextColumn get id => text().clientDefault(newId)();
  TextColumn get type => text().withDefault(const Constant('base'))();
  DateTimeColumn get created => dateTime()();
  DateTimeColumn get updated => dateTime()();
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

class StringListMapper extends TypeConverter<List<String>, String> {
  const StringListMapper();

  @override
  List<String> fromSql(String fromDb) => jsonDecode(fromDb).cast<String>();

  @override
  String toSql(List<String> value) => jsonEncode(value);
}

class SchemaFieldListMapper extends TypeConverter<List<SchemaField>, String> {
  const SchemaFieldListMapper();

  @override
  List<SchemaField> fromSql(String fromDb) =>
      (jsonDecode(fromDb) as List).map((e) => SchemaField.fromJson(e)).toList();

  @override
  String toSql(List<SchemaField> value) =>
      jsonEncode(value.map((e) => e.toJson()).toList());
}

String newId() {
  const chars =
      '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
  shortid.characters(chars);
  return shortid.generate().padLeft(15, '0');
}
