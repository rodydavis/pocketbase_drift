import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:pocketbase/pocketbase.dart';

import 'connection/connection.dart' as impl;
import 'daos/admins.dart';
import 'daos/records.dart';
import 'daos/collections.dart';
import 'tables.dart';

export 'daos/records.dart';
export 'daos/collections.dart';

part 'database.g.dart';

@DriftDatabase(
  tables: [
    Records,
    Collections,
    AuthTokens,
    Admins,
  ],
  daos: [
    RecordsDao,
    CollectionsDao,
    AdminsDao,
  ],
  include: {
    'sql/search.drift',
  },
)
class DataBase extends _$DataBase {
  DataBase(DatabaseConnection connection) : super.connect(connection);

  factory DataBase.file({
    String dbName = 'pocketbase.db',
    bool logStatements = false,
  }) {
    return DataBase(impl.connect(
      dbName,
      logStatements: logStatements,
    ));
  }

  @override
  int get schemaVersion => 3;

  Future<List<RecordModel>> search(
    String query, {
    String? collectionId,
  }) async {
    final results = await _search(query).get();
    final items = results.map((e) => e.r.toModel()).toList();
    if (collectionId == null) return items;
    return items.where((item) => item.collectionId == collectionId).toList();
  }

  String generateId() => newId();

  Future<AuthToken?> getAuthToken() async {
    final tokens = await select(authTokens).get();
    if (tokens.isEmpty) return null;
    return tokens.first;
  }

  Future<void> setAuthToken(AuthTokensCompanion token) async {
    final tokens = await select(authTokens).get();
    if (tokens.isNotEmpty) {
      await removeAuthToken();
    }
    await into(authTokens).insert(token);
  }

  Future<void> removeAuthToken() async {
    await delete(authTokens).go();
  }

  String queryBuilder(
    String table, {
    String? fields,
    String? filter,
    String? sort,
  }) {
    final baseFields = <String>[
      "id",
      "created",
      "updated",
      "collectionId",
      "collectionName",
      "expand",
    ];

    String fixField(String field) {
      field = field.trim();
      if (baseFields.contains(field)) return field;
      return "json_extract(records.data, '\$.$field') as $field";
    }

    final sb = StringBuffer();
    sb.write('SELECT ');
    if (fields != null && fields.isNotEmpty) {
      final items = fields.split(',');
      for (var i = 0; i < items.length; i++) {
        final item = items[i];
        sb.write(fixField(item));
        if (i < items.length - 1) {
          sb.write(', ');
        }
      }
    } else {
      sb.write('*');
    }
    sb.write(' FROM records');
    sb.write(' WHERE collectionName = "$table"');
    if (filter != null && filter.isNotEmpty) {
      // Replace && and || with AND and OR
      if (filter.startsWith('(') && filter.endsWith(')')) {
        filter = filter.substring(1, filter.length - 1);
      }
      filter = filter.replaceAll('&&', 'AND').replaceAll('||', 'OR');
      // Replace fields with json_extract
      // = Equal
      // != NOT equal
      // > Greater than
      // >= Greater than or equal
      // < Less than
      // <= Less than or equal
      // ~ Like/Contains (if not specified auto wraps the right string OPERAND in a "%" for wildcard match)
      // !~ NOT Like/Contains (if not specified auto wraps the right string OPERAND in a "%" for wildcard match)
      // ?= Any/At least one of Equal
      // ?!= Any/At least one of NOT equal
      // ?> Any/At least one of Greater than
      // ?>= Any/At least one of Greater than or equal
      // ?< Any/At least one of Less than
      // ?<= Any/At least one of Less than or equal
      // ?~ Any/At least one of Like/Contains (if not specified auto wraps the right string OPERAND in a "%" for wildcard match)
      // ?!~ Any/At least one of NOT Like/Contains (if not specified auto wraps the right string OPERAND in a "%" for wildcard match)
      filter = filter.replaceAllMapped(
        RegExp(
          r'(\w+)\s*(=|!=|>|<|>=|<=|~|!~|\?=|\?!=|\?>|\?>=|\?<|\?<=|\?~|\?!~)\s*(\w+)',
        ),
        (match) {
          final field = match.group(1);
          final op = match.group(2);
          final value = match.group(3);
          return '${fixField(field!)} $op $value';
        },
      );
      sb.write(' AND ($filter)');
    }
    if (sort != null && sort.isNotEmpty) {
      // Example: -created,id
      // - DESC, + ASC
      final parts = sort.split(',');
      if (parts.isNotEmpty) {
        sb.write(' ORDER BY ');
        for (var i = 0; i < parts.length; i++) {
          final part = parts[i];
          if (part.startsWith('-')) {
            sb.write(part.substring(1));
            sb.write(' DESC');
          } else if (part.startsWith('+')) {
            sb.write(part.substring(1));
            sb.write(' ASC');
          } else {
            sb.write(part);
            sb.write(' ASC');
          }
          if (i < parts.length - 1) {
            sb.write(', ');
          }
        }
      }
    }
    return sb.toString();
  }

  Selectable<Map<String, dynamic>> $query(
    Collection collection, {
    String? expand,
    String? fields,
    String? filter,
    String? sort,
    List<Variable<Object>> variables = const [],
  }) {
    final query = queryBuilder(
      collection.name,
      fields: fields,
      filter: filter,
      sort: sort,
    );
    return customSelect(
      query,
      variables: variables,
      readsFrom: {records},
    ).asyncMap((r) async {
      final collections = await select(this.collections).get();
      final record = parseRow(r);
      if (expand != null && expand.isNotEmpty) {
        record['expand'] = {};
        final targets = expand.split(',').map((e) => e.trim()).toList();
        for (final target in targets) {
          final levels = target.split('.');
          // Max 6 levels supported
          if (levels.length > 6) {
            throw Exception('Max 6 levels expand supported');
          }

          final nestedExpand =
              levels.length == 1 ? null : levels.skip(1).join('.');
          final targetField = levels.first;

          // check for indirect expand=comments(post).user
          if (targetField.contains('(') && targetField.contains(')')) {
            // final tCollection = targetField.substring(
            //   0,
            //   targetField.indexOf('('),
            // );
            // final tField = targetField.substring(
            //   targetField.indexOf('(') + 1,
            //   targetField.indexOf(')'),
            // );
            // row.data['expand']['$tCollection($tField)'] = [];
            throw UnimplementedError('Indirect expand not supported yet');
          }

          // Match field to relation
          final c = collections.firstWhere((e) => e.id == collection.id);
          final schemaField = c.schema.firstWhere(
            (e) => e.name == targetField,
          );
          final targetCollection = collections.firstWhere(
            (e) => e.id == schemaField.options['collectionId'],
          );
          final isSingle = schemaField.options['maxSelect'] == 1;
          final id = record[targetField] as String?;
          record['expand'][targetField] = [];
          if (id != null) {
            final query = $query(
              targetCollection,
              expand: nestedExpand ?? '',
              fields: fields,
              filter: 'id="$id"',
              variables: [],
            );
            if (isSingle) {
              final result = await query.getSingleOrNull();
              if (result != null) {
                record['expand'][targetField]!.add(result);
              }
            } else {
              final result = await query.get();
              final items = result.toList();
              record['expand'][targetField]!.addAll(items);
            }
          }
        }
      }
      return record;
    });
  }

  Map<String, dynamic> parseRow(QueryRow row) {
    const fields = [
      'id',
      'collectionId',
      'collectionName',
      'created',
      'updated',
    ];
    final result = <String, dynamic>{};

    if (row.data.containsKey('data')) {
      final data = jsonDecode(row.read<String>('data')) as Map<String, dynamic>;
      result.addAll(data);
    } else {
      result.addAll(row.data);
    }

    for (final field in row.data.keys) {
      if (fields.contains(field)) {
        if (field == 'created' || field == 'updated') {
          result[field] = row.readNullable<DateTime>(field)?.toIso8601String();
          continue;
        } else {
          result[field] = row.readNullable<String>(field);
        }
        continue;
      }
    }

    return result;
  }

  /// Validates data against collection schema
  ///
  /// Throws exception if data is invalid for each field
  ///
  /// Returns true if data is valid
  bool validateData(Collection collection, Map<String, dynamic> data) {
    for (final field in collection.schema) {
      final value = data[field.name];
      if (field.required && value == null) {
        throw Exception('Field ${field.name} is required');
      }
      if (field.type == 'number') {
        if (value != null && num.tryParse(value) == null) {
          throw Exception('Field ${field.name} must be a valid number');
        }
      }
      if (field.type == 'bool') {
        if (value != null && value != true && value != false) {
          throw Exception('Field ${field.name} must be a valid boolean');
        }
      }
      if (field.type == 'date') {
        if (value != null && DateTime.tryParse(value) == null) {
          throw Exception('Field ${field.name} must be a valid date');
        }
      }
      if (field.type == 'text' || field.type == 'editor') {
        if (value != null && value is! String) {
          throw Exception('Field ${field.name} must be a valid string');
        }
      }
      if (field.type == 'url') {
        if (value != null && Uri.tryParse(value) == null) {
          throw Exception('Field ${field.name} must be a valid url');
        }
      }
      if (field.type == 'email') {
        if (value != null && value is! String) {
          // TODO: Regex to validate email?
          throw Exception('Field ${field.name} must be a valid email');
        }
      }
      if (field.type == 'select' ||
          field.type == 'file' ||
          field.type == 'relation') {
        if (value != null && field.options['maxSelect'] != null) {
          if (field.options['maxSelect'] == 1 && value is! String) {
            throw Exception('Field ${field.name} must be a valid string');
          } else if (field.options['maxSelect'] != 1 && value is! List) {
            throw Exception('Field ${field.name} must be a valid list');
          }
        }
      }
    }
    return true;
  }

  Future<Map<String, dynamic>> $create(
    Collection collection,
    Map<String, dynamic> data, {
    bool? synced,
    bool? deleted = false,
    bool? isNew,
    bool? local,
    bool validate = false,
  }) async {
    if (data['id'] == '') data.remove('id');
    final id = data['id'] as String?;
    data.remove('id');

    if (validate) validateData(collection, data);

    final created = data['created'] ?? DateTime.now().toIso8601String();
    final updated = data['updated'] ?? DateTime.now().toIso8601String();

    final record = RecordsCompanion.insert(
      id: id != null ? Value(id) : const Value.absent(),
      collectionId: collection.id,
      collectionName: collection.name,
      data: data,
      metadata: {
        'synced': synced,
        'deleted': deleted,
        if (isNew != null) 'new': isNew,
        if (local != null) 'local': local,
      },
      created: DateTime.parse(created),
      updated: DateTime.parse(updated),
    );

    int rowId = -1;

    if (id != null) {
      final existing = await (select(records)
            ..where((r) => r.collectionId.equals(collection.id))
            ..where((r) => r.id.equals(id)))
          .getSingleOrNull();
      if (existing != null) {
        rowId = await (update(records)
              ..where((r) => r.id.equals(id))
              ..where((r) => r.collectionId.equals(collection.id)))
            .write(record);
      }
    }

    if (rowId == -1) {
      rowId = await into(records).insert(record);
    }

    if (rowId == -1) {
      throw Exception('Failed to create record');
    }

    final q = select(records)..where((r) => r.rowId.equals(rowId));
    final result = await q.getSingle();
    return $query(collection, filter: 'id = "${result.id}"').getSingle();
  }

  Future<Map<String, dynamic>> $update(
    Collection collection,
    String id,
    Map<String, dynamic> data, {
    bool? synced,
    bool? deleted = false,
    bool? isNew,
    bool? local,
    bool validate = false,
  }) {
    return $create(
      collection,
      {...data, 'id': id},
      synced: synced,
      deleted: deleted,
      isNew: isNew,
      local: local,
      validate: validate,
    );
  }

  Future<void> $delete(
    Collection collection,
    String id,
  ) async {
    await (delete(records)
          ..where((r) => r.collectionId.equals(collection.id))
          ..where((r) => r.id.equals(id)))
        .go();
  }
}
