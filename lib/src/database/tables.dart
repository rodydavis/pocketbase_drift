import 'dart:convert';

import 'package:drift/drift.dart';

@DataClassName('Record')
class Records extends Table with AutoIncrementingPrimaryKey {
  TextColumn get rowId => text()();
  TextColumn get collectionId => text()();
  TextColumn get collectionName => text()();
  TextColumn get data => text().map(const JsonMapper())();
  BoolColumn get deleted => boolean().nullable()();
  TextColumn get created => text()();
  TextColumn get updated => text()();

  @override
  List<Set<Column<Object>>>? get uniqueKeys => [
        {collectionId, rowId},
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

// abstract class RawJson<T> {
//   RawJson(this.value);
//   final T value;

//   String toJson() => jsonEncode(value);

//   static RawJson fromJson(String source) {
//     final decoded = json.decode(source);
//     if (decoded is List<dynamic>) {
//       return JsonList(decoded);
//     }
//     return JsonMap(decoded);
//   }
// }

// class JsonMap extends RawJson<Map<String, dynamic>> {
//   JsonMap(super.value);
// }

// class JsonList extends RawJson<List<dynamic>> {
//   JsonList(super.value);
// }
