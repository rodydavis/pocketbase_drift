import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:shortid/shortid.dart';

@DataClassName('Service')
class Services extends Table {
  TextColumn get id => text().clientDefault(newId)();
  TextColumn get data => text().map(const JsonMapper())();
  TextColumn get service => text()();
  TextColumn get created => text().nullable()();
  TextColumn get updated => text().nullable()();

  @override
  Set<Column<Object>>? get primaryKey => {id, service};
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
  List<SchemaField> fromSql(String fromDb) => (jsonDecode(fromDb) as List).map((e) => SchemaField.fromJson(e)).toList();

  @override
  String toSql(List<SchemaField> value) => jsonEncode(value.map((e) => e.toJson()).toList());
}

String newId() {
  const chars = '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
  shortid.characters(chars);
  return shortid.generate().padLeft(15, '0');
}
