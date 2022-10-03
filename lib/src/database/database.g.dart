// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// **************************************************************************
// DriftDatabaseGenerator
// **************************************************************************

// ignore_for_file: type=lint
class Record extends DataClass implements Insertable<Record> {
  final int id;
  final String rowId;
  final String collectionId;
  final String collectionName;
  final Map<String, dynamic> data;
  final bool? deleted;
  final String created;
  final String updated;
  const Record(
      {required this.id,
      required this.rowId,
      required this.collectionId,
      required this.collectionName,
      required this.data,
      this.deleted,
      required this.created,
      required this.updated});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['row_id'] = Variable<String>(rowId);
    map['collection_id'] = Variable<String>(collectionId);
    map['collection_name'] = Variable<String>(collectionName);
    {
      final converter = $RecordsTable.$converter0;
      map['data'] = Variable<String>(converter.toSql(data));
    }
    if (!nullToAbsent || deleted != null) {
      map['deleted'] = Variable<bool>(deleted);
    }
    map['created'] = Variable<String>(created);
    map['updated'] = Variable<String>(updated);
    return map;
  }

  RecordsCompanion toCompanion(bool nullToAbsent) {
    return RecordsCompanion(
      id: Value(id),
      rowId: Value(rowId),
      collectionId: Value(collectionId),
      collectionName: Value(collectionName),
      data: Value(data),
      deleted: deleted == null && nullToAbsent
          ? const Value.absent()
          : Value(deleted),
      created: Value(created),
      updated: Value(updated),
    );
  }

  factory Record.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Record(
      id: serializer.fromJson<int>(json['id']),
      rowId: serializer.fromJson<String>(json['rowId']),
      collectionId: serializer.fromJson<String>(json['collectionId']),
      collectionName: serializer.fromJson<String>(json['collectionName']),
      data: serializer.fromJson<Map<String, dynamic>>(json['data']),
      deleted: serializer.fromJson<bool?>(json['deleted']),
      created: serializer.fromJson<String>(json['created']),
      updated: serializer.fromJson<String>(json['updated']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'rowId': serializer.toJson<String>(rowId),
      'collectionId': serializer.toJson<String>(collectionId),
      'collectionName': serializer.toJson<String>(collectionName),
      'data': serializer.toJson<Map<String, dynamic>>(data),
      'deleted': serializer.toJson<bool?>(deleted),
      'created': serializer.toJson<String>(created),
      'updated': serializer.toJson<String>(updated),
    };
  }

  Record copyWith(
          {int? id,
          String? rowId,
          String? collectionId,
          String? collectionName,
          Map<String, dynamic>? data,
          Value<bool?> deleted = const Value.absent(),
          String? created,
          String? updated}) =>
      Record(
        id: id ?? this.id,
        rowId: rowId ?? this.rowId,
        collectionId: collectionId ?? this.collectionId,
        collectionName: collectionName ?? this.collectionName,
        data: data ?? this.data,
        deleted: deleted.present ? deleted.value : this.deleted,
        created: created ?? this.created,
        updated: updated ?? this.updated,
      );
  @override
  String toString() {
    return (StringBuffer('Record(')
          ..write('id: $id, ')
          ..write('rowId: $rowId, ')
          ..write('collectionId: $collectionId, ')
          ..write('collectionName: $collectionName, ')
          ..write('data: $data, ')
          ..write('deleted: $deleted, ')
          ..write('created: $created, ')
          ..write('updated: $updated')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id, rowId, collectionId, collectionName, data, deleted, created, updated);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Record &&
          other.id == this.id &&
          other.rowId == this.rowId &&
          other.collectionId == this.collectionId &&
          other.collectionName == this.collectionName &&
          other.data == this.data &&
          other.deleted == this.deleted &&
          other.created == this.created &&
          other.updated == this.updated);
}

class RecordsCompanion extends UpdateCompanion<Record> {
  final Value<int> id;
  final Value<String> rowId;
  final Value<String> collectionId;
  final Value<String> collectionName;
  final Value<Map<String, dynamic>> data;
  final Value<bool?> deleted;
  final Value<String> created;
  final Value<String> updated;
  const RecordsCompanion({
    this.id = const Value.absent(),
    this.rowId = const Value.absent(),
    this.collectionId = const Value.absent(),
    this.collectionName = const Value.absent(),
    this.data = const Value.absent(),
    this.deleted = const Value.absent(),
    this.created = const Value.absent(),
    this.updated = const Value.absent(),
  });
  RecordsCompanion.insert({
    this.id = const Value.absent(),
    required String rowId,
    required String collectionId,
    required String collectionName,
    required Map<String, dynamic> data,
    this.deleted = const Value.absent(),
    required String created,
    required String updated,
  })  : rowId = Value(rowId),
        collectionId = Value(collectionId),
        collectionName = Value(collectionName),
        data = Value(data),
        created = Value(created),
        updated = Value(updated);
  static Insertable<Record> custom({
    Expression<int>? id,
    Expression<String>? rowId,
    Expression<String>? collectionId,
    Expression<String>? collectionName,
    Expression<String>? data,
    Expression<bool>? deleted,
    Expression<String>? created,
    Expression<String>? updated,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (rowId != null) 'row_id': rowId,
      if (collectionId != null) 'collection_id': collectionId,
      if (collectionName != null) 'collection_name': collectionName,
      if (data != null) 'data': data,
      if (deleted != null) 'deleted': deleted,
      if (created != null) 'created': created,
      if (updated != null) 'updated': updated,
    });
  }

  RecordsCompanion copyWith(
      {Value<int>? id,
      Value<String>? rowId,
      Value<String>? collectionId,
      Value<String>? collectionName,
      Value<Map<String, dynamic>>? data,
      Value<bool?>? deleted,
      Value<String>? created,
      Value<String>? updated}) {
    return RecordsCompanion(
      id: id ?? this.id,
      rowId: rowId ?? this.rowId,
      collectionId: collectionId ?? this.collectionId,
      collectionName: collectionName ?? this.collectionName,
      data: data ?? this.data,
      deleted: deleted ?? this.deleted,
      created: created ?? this.created,
      updated: updated ?? this.updated,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (rowId.present) {
      map['row_id'] = Variable<String>(rowId.value);
    }
    if (collectionId.present) {
      map['collection_id'] = Variable<String>(collectionId.value);
    }
    if (collectionName.present) {
      map['collection_name'] = Variable<String>(collectionName.value);
    }
    if (data.present) {
      final converter = $RecordsTable.$converter0;
      map['data'] = Variable<String>(converter.toSql(data.value));
    }
    if (deleted.present) {
      map['deleted'] = Variable<bool>(deleted.value);
    }
    if (created.present) {
      map['created'] = Variable<String>(created.value);
    }
    if (updated.present) {
      map['updated'] = Variable<String>(updated.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RecordsCompanion(')
          ..write('id: $id, ')
          ..write('rowId: $rowId, ')
          ..write('collectionId: $collectionId, ')
          ..write('collectionName: $collectionName, ')
          ..write('data: $data, ')
          ..write('deleted: $deleted, ')
          ..write('created: $created, ')
          ..write('updated: $updated')
          ..write(')'))
        .toString();
  }
}

class $RecordsTable extends Records with TableInfo<$RecordsTable, Record> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RecordsTable(this.attachedDatabase, [this._alias]);
  final VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints: 'PRIMARY KEY AUTOINCREMENT');
  final VerificationMeta _rowIdMeta = const VerificationMeta('rowId');
  @override
  late final GeneratedColumn<String> rowId = GeneratedColumn<String>(
      'row_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  final VerificationMeta _collectionIdMeta =
      const VerificationMeta('collectionId');
  @override
  late final GeneratedColumn<String> collectionId = GeneratedColumn<String>(
      'collection_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  final VerificationMeta _collectionNameMeta =
      const VerificationMeta('collectionName');
  @override
  late final GeneratedColumn<String> collectionName = GeneratedColumn<String>(
      'collection_name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  final VerificationMeta _dataMeta = const VerificationMeta('data');
  @override
  late final GeneratedColumnWithTypeConverter<Map<String, dynamic>, String>
      data = GeneratedColumn<String>('data', aliasedName, false,
              type: DriftSqlType.string, requiredDuringInsert: true)
          .withConverter<Map<String, dynamic>>($RecordsTable.$converter0);
  final VerificationMeta _deletedMeta = const VerificationMeta('deleted');
  @override
  late final GeneratedColumn<bool> deleted = GeneratedColumn<bool>(
      'deleted', aliasedName, true,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: 'CHECK (deleted IN (0, 1))');
  final VerificationMeta _createdMeta = const VerificationMeta('created');
  @override
  late final GeneratedColumn<String> created = GeneratedColumn<String>(
      'created', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  final VerificationMeta _updatedMeta = const VerificationMeta('updated');
  @override
  late final GeneratedColumn<String> updated = GeneratedColumn<String>(
      'updated', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        rowId,
        collectionId,
        collectionName,
        data,
        deleted,
        created,
        updated
      ];
  @override
  String get aliasedName => _alias ?? 'records';
  @override
  String get actualTableName => 'records';
  @override
  VerificationContext validateIntegrity(Insertable<Record> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('row_id')) {
      context.handle(
          _rowIdMeta, rowId.isAcceptableOrUnknown(data['row_id']!, _rowIdMeta));
    } else if (isInserting) {
      context.missing(_rowIdMeta);
    }
    if (data.containsKey('collection_id')) {
      context.handle(
          _collectionIdMeta,
          collectionId.isAcceptableOrUnknown(
              data['collection_id']!, _collectionIdMeta));
    } else if (isInserting) {
      context.missing(_collectionIdMeta);
    }
    if (data.containsKey('collection_name')) {
      context.handle(
          _collectionNameMeta,
          collectionName.isAcceptableOrUnknown(
              data['collection_name']!, _collectionNameMeta));
    } else if (isInserting) {
      context.missing(_collectionNameMeta);
    }
    context.handle(_dataMeta, const VerificationResult.success());
    if (data.containsKey('deleted')) {
      context.handle(_deletedMeta,
          deleted.isAcceptableOrUnknown(data['deleted']!, _deletedMeta));
    }
    if (data.containsKey('created')) {
      context.handle(_createdMeta,
          created.isAcceptableOrUnknown(data['created']!, _createdMeta));
    } else if (isInserting) {
      context.missing(_createdMeta);
    }
    if (data.containsKey('updated')) {
      context.handle(_updatedMeta,
          updated.isAcceptableOrUnknown(data['updated']!, _updatedMeta));
    } else if (isInserting) {
      context.missing(_updatedMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
        {collectionId, rowId},
      ];
  @override
  Record map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Record(
      id: attachedDatabase.options.types
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      rowId: attachedDatabase.options.types
          .read(DriftSqlType.string, data['${effectivePrefix}row_id'])!,
      collectionId: attachedDatabase.options.types
          .read(DriftSqlType.string, data['${effectivePrefix}collection_id'])!,
      collectionName: attachedDatabase.options.types.read(
          DriftSqlType.string, data['${effectivePrefix}collection_name'])!,
      data: $RecordsTable.$converter0.fromSql(attachedDatabase.options.types
          .read(DriftSqlType.string, data['${effectivePrefix}data'])!),
      deleted: attachedDatabase.options.types
          .read(DriftSqlType.bool, data['${effectivePrefix}deleted']),
      created: attachedDatabase.options.types
          .read(DriftSqlType.string, data['${effectivePrefix}created'])!,
      updated: attachedDatabase.options.types
          .read(DriftSqlType.string, data['${effectivePrefix}updated'])!,
    );
  }

  @override
  $RecordsTable createAlias(String alias) {
    return $RecordsTable(attachedDatabase, alias);
  }

  static TypeConverter<Map<String, dynamic>, String> $converter0 =
      const JsonMapper();
}

class TextEntrie extends DataClass implements Insertable<TextEntrie> {
  final String data;
  const TextEntrie({required this.data});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['data'] = Variable<String>(data);
    return map;
  }

  TextEntriesCompanion toCompanion(bool nullToAbsent) {
    return TextEntriesCompanion(
      data: Value(data),
    );
  }

  factory TextEntrie.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TextEntrie(
      data: serializer.fromJson<String>(json['data']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'data': serializer.toJson<String>(data),
    };
  }

  TextEntrie copyWith({String? data}) => TextEntrie(
        data: data ?? this.data,
      );
  @override
  String toString() {
    return (StringBuffer('TextEntrie(')
          ..write('data: $data')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => data.hashCode;
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TextEntrie && other.data == this.data);
}

class TextEntriesCompanion extends UpdateCompanion<TextEntrie> {
  final Value<String> data;
  const TextEntriesCompanion({
    this.data = const Value.absent(),
  });
  TextEntriesCompanion.insert({
    required String data,
  }) : data = Value(data);
  static Insertable<TextEntrie> custom({
    Expression<String>? data,
  }) {
    return RawValuesInsertable({
      if (data != null) 'data': data,
    });
  }

  TextEntriesCompanion copyWith({Value<String>? data}) {
    return TextEntriesCompanion(
      data: data ?? this.data,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (data.present) {
      map['data'] = Variable<String>(data.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TextEntriesCompanion(')
          ..write('data: $data')
          ..write(')'))
        .toString();
  }
}

class TextEntries extends Table
    with
        TableInfo<TextEntries, TextEntrie>,
        VirtualTableInfo<TextEntries, TextEntrie> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  TextEntries(this.attachedDatabase, [this._alias]);
  final VerificationMeta _dataMeta = const VerificationMeta('data');
  late final GeneratedColumn<String> data = GeneratedColumn<String>(
      'data', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      $customConstraints: '');
  @override
  List<GeneratedColumn> get $columns => [data];
  @override
  String get aliasedName => _alias ?? 'text_entries';
  @override
  String get actualTableName => 'text_entries';
  @override
  VerificationContext validateIntegrity(Insertable<TextEntrie> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('data')) {
      context.handle(
          _dataMeta, this.data.isAcceptableOrUnknown(data['data']!, _dataMeta));
    } else if (isInserting) {
      context.missing(_dataMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => <GeneratedColumn>{};
  @override
  TextEntrie map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TextEntrie(
      data: attachedDatabase.options.types
          .read(DriftSqlType.string, data['${effectivePrefix}data'])!,
    );
  }

  @override
  TextEntries createAlias(String alias) {
    return TextEntries(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
  @override
  String get moduleAndArgs => 'fts5(data, content=records, content_rowid=id)';
}

abstract class _$PocketBaseDatabase extends GeneratedDatabase {
  _$PocketBaseDatabase(QueryExecutor e) : super(e);
  _$PocketBaseDatabase.connect(DatabaseConnection c) : super.connect(c);
  late final $RecordsTable records = $RecordsTable(this);
  late final TextEntries textEntries = TextEntries(this);
  late final Trigger recordsInsert = Trigger(
      'CREATE TRIGGER records_insert AFTER INSERT ON records BEGIN INSERT INTO text_entries ("rowid", data) VALUES (new.id, new.data);END',
      'records_insert');
  late final Trigger recordsDelete = Trigger(
      'CREATE TRIGGER records_delete AFTER DELETE ON records BEGIN INSERT INTO text_entries (text_entries, "rowid", data) VALUES (\'delete\', old.id, old.data);END',
      'records_delete');
  late final Trigger recordsUpdate = Trigger(
      'CREATE TRIGGER records_update AFTER UPDATE ON records BEGIN INSERT INTO text_entries (text_entries, "rowid", data) VALUES (\'delete\', new.id, new.data);INSERT INTO text_entries ("rowid", data) VALUES (new.id, new.data);END',
      'records_update');
  Selectable<SearchResult> _search(String query) {
    return customSelect(
        'SELECT"r"."id" AS "nested_0.id", "r"."row_id" AS "nested_0.row_id", "r"."collection_id" AS "nested_0.collection_id", "r"."collection_name" AS "nested_0.collection_name", "r"."data" AS "nested_0.data", "r"."deleted" AS "nested_0.deleted", "r"."created" AS "nested_0.created", "r"."updated" AS "nested_0.updated" FROM text_entries INNER JOIN records AS r ON r.id = text_entries."rowid" WHERE text_entries MATCH ?1 ORDER BY rank',
        variables: [
          Variable<String>(query)
        ],
        readsFrom: {
          textEntries,
          records,
        }).asyncMap((QueryRow row) async {
      return SearchResult(
        r: await records.mapFromRow(row, tablePrefix: 'nested_0'),
      );
    });
  }

  @override
  Iterable<TableInfo<Table, dynamic>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities =>
      [records, textEntries, recordsInsert, recordsDelete, recordsUpdate];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules(
        [
          WritePropagation(
            on: TableUpdateQuery.onTableName('records',
                limitUpdateKind: UpdateKind.insert),
            result: [
              TableUpdate('text_entries', kind: UpdateKind.insert),
            ],
          ),
          WritePropagation(
            on: TableUpdateQuery.onTableName('records',
                limitUpdateKind: UpdateKind.delete),
            result: [
              TableUpdate('text_entries', kind: UpdateKind.insert),
            ],
          ),
          WritePropagation(
            on: TableUpdateQuery.onTableName('records',
                limitUpdateKind: UpdateKind.update),
            result: [
              TableUpdate('text_entries', kind: UpdateKind.insert),
            ],
          ),
        ],
      );
}

class SearchResult {
  final Record r;
  SearchResult({
    required this.r,
  });
}
