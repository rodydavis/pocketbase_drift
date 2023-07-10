import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:shortid/shortid.dart';

// @DataClassName('BlobFile')
// class BlobFiles extends Table with AutoIncrementingPrimaryKey {
//   TextColumn get name => text()();
//   BlobColumn get file => blob()();
//   DateTimeColumn get created => dateTime()();
//   DateTimeColumn get updated => dateTime()();
// }

// @DataClassName('Mutation')
// class Mutations extends Table with AutoIncrementingPrimaryKey {
//   TextColumn get path => text()();
//   TextColumn get method => text()();
//   TextColumn get body => text().map(const JsonMapper())();
//   TextColumn get query => text().map(const JsonMapper())();
//   TextColumn get headers => text().map(const JsonMapper())();
//   TextColumn get files => text().map(const StringListMapper())();
//   DateTimeColumn get created => dateTime()();
// }

@DataClassName('AuthToken')
class AuthTokens extends Table with AutoIncrementingPrimaryKey {
  TextColumn get token => text()();
  DateTimeColumn get created => dateTime()();
}

abstract class ServiceRecord extends DataClass implements Jsonable {
  const ServiceRecord();
  String get id;
  DateTime get created;
  DateTime get updated;
}

// @DataClassName('Item', extending: ServiceRecord)
// class Items extends Table with ServiceRecords {
//   TextColumn get table => text()();
//   TextColumn get data => text().map(const JsonMapper())();

//   @override
//   Set<Column<Object>>? get primaryKey => {id, table};
// }

mixin ServiceRecords on Table {
  TextColumn get id => text().clientDefault(newId)();
  TextColumn get metadata => text().map(const JsonMapper())();
  //.withDefault(const Constant('{}'))
  DateTimeColumn get created => dateTime()();
  DateTimeColumn get updated => dateTime()();
}

mixin AutoIncrementingPrimaryKey on Table {
  IntColumn get id => integer().autoIncrement()();

  @override
  Set<Column<Object>>? get primaryKey => {id};
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
