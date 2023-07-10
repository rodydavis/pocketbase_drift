import 'package:drift/drift.dart';

import '../database.dart';
import '../tables.dart';

abstract class ServiceRecordsDao<TableDsl extends ServiceRecords,
    T extends ServiceRecord> extends DatabaseAccessor<DataBase> {
  ServiceRecordsDao(DataBase db) : super(db);

  TableInfo<TableDsl, T> get table;

  SimpleSelectStatement<TableDsl, T> target({
    required String? id,
    required int? page,
    required int? perPage,
    required String? sort,
    required String? fields,
    required String? expand,
    required String? filter,
  }) {
    var query = select(table);
    if (id != null) {
      query = query..where((t) => t.id.equals(id));
    }
    if (filter != null) {
      // filter example: id='abc' && created>'2021-01-01'
      if (filter.startsWith('(') && filter.endsWith(')')) {
        filter = filter.substring(1, filter.length - 1);
      }
      // const and = '&&';
      // const or = '||';
      // var idx = 0;
      // while (idx < filter.length) {
      //   final andIdx = filter.indexOf(and, idx);
      //   final orIdx = filter.indexOf(or, idx);
      //   final endIdx = andIdx == -1 && orIdx == -1
      //       ? filter.length
      //       : andIdx == -1
      //           ? orIdx
      //           : orIdx == -1
      //               ? andIdx
      //               : andIdx < orIdx
      //                   ? andIdx
      //                   : orIdx;
      //   final part = filter.substring(idx, endIdx);
      //   final eqIdx = part.indexOf('=');
      //   final gtIdx = part.indexOf('>');
      //   final ltIdx = part.indexOf('<');
      //   final gteIdx = part.indexOf('>=');
      //   final lteIdx = part.indexOf('<=');
      //   final opIdx = eqIdx == -1
      //       ? gtIdx == -1
      //           ? ltIdx == -1
      //               ? gteIdx == -1
      //                   ? lteIdx == -1
      //                       ? -1
      //                       : lteIdx
      //                   : gteIdx
      //               : ltIdx
      //           : gtIdx
      //       : eqIdx;
      //   if (opIdx == -1) {
      //     throw ArgumentError.value(filter, 'filter', 'Invalid filter');
      //   }
      //   final op = part.substring(opIdx, opIdx + 2);
      //   final field = part.substring(0, opIdx);
      //   final value = part.substring(opIdx + 2);
      //   switch (op) {
      //     case '==':
      //       query = query..where((t) => t[field].equals(value));
      //       break;
      //     case '>=':
      //       query = query..where((t) => t[field].isBiggerOrEqual(value));
      //       break;
      //     case '<=':
      //       query = query..where((t) => t[field].isSmallerOrEqual(value));
      //       break;
      //     case '>':
      //       query = query..where((t) => t[field].isBiggerThan(value));
      //       break;
      //     case '<':
      //       query = query..where((t) => t[field].isSmallerThan(value));
      //       break;
      //     default:
      //       throw ArgumentError.value(filter, 'filter', 'Invalid filter');
      //   }
      //   idx = endIdx + 2;
      // }
    }
    if (page != null && perPage != null) {
      final limit = perPage;
      final offset = (page - 1) * perPage;
      query = query..limit(limit, offset: offset);
    }
    return query;
  }

  Future<List<T>> getAll({
    int? page,
    int? perPage,
    String? sort,
    String? fields,
    String? expand,
    String? filter,
  }) {
    return target(
      page: page,
      perPage: perPage,
      sort: sort,
      fields: fields,
      expand: expand,
      filter: filter,
      id: null,
    ).get();
  }

  Stream<List<T>> watchAll({
    int? page,
    int? perPage,
    String? sort,
    String? fields,
    String? expand,
    String? filter,
  }) {
    return target(
      page: page,
      perPage: perPage,
      sort: sort,
      fields: fields,
      expand: expand,
      filter: filter,
      id: null,
    ).watch();
  }

  Future<T?> get(
    String id, {
    String? fields,
    String? expand,
  }) {
    return target(
      id: id,
      page: null,
      perPage: null,
      sort: null,
      filter: null,
      fields: fields,
      expand: expand,
    ).getSingleOrNull();
  }

  Stream<T?> watch(
    String id, {
    String? fields,
    String? expand,
  }) {
    return target(
      id: id,
      page: null,
      perPage: null,
      sort: null,
      filter: null,
      fields: fields,
      expand: expand,
    ).watchSingleOrNull();
  }

  Future<int> getCount() async {
    final count = countAll();
    var q = selectOnly(table)..addColumns([count]);
    return q.map((row) => row.read(count)!).getSingle();
  }

  Future<void> deleteItem(String id) async {
    var query = delete(table);
    query = query..where((t) => t.id.equals(id));
    await query.go();
  }

  Insertable<T> toCompanion(T data);

  Future<String> createItem(T data) async {
    final companion = toCompanion(data);
    final item = await into(table).insertReturning(
      companion,
      mode: InsertMode.insertOrReplace,
    );
    return item.id;
  }

  // Future<void> updateItem(T data) async {
  //   final companion = toCompanion(data);
  //   var query = update(table);
  //   query = query..where((tbl) => tbl.id.equals(data.id));
  //   await query.write(companion);
  // }

  // Future<String> createItem(T data);

  Future<void> updateItem(T data);

  // Future<void> addAll(List<T> items) async {
  //   return transaction(() async {
  //     // TODO: Batch?
  //     for (final item in items) {
  //       var query = select(table);
  //       query = query..where((tbl) => tbl.id.equals(item.id));
  //       final existing = await query.getSingleOrNull();
  //       if (existing != null) {
  //         await updateItem(item);
  //       } else {
  //         await createItem(item);
  //       }
  //     }
  //   });
  // }
}
