// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $CollectionsTable extends Collections
    with TableInfo<$CollectionsTable, Collection> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CollectionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      clientDefault: newId);
  static const VerificationMeta _metadataMeta =
      const VerificationMeta('metadata');
  @override
  late final GeneratedColumnWithTypeConverter<Map<String, dynamic>, String>
      metadata = GeneratedColumn<String>('metadata', aliasedName, false,
              type: DriftSqlType.string, requiredDuringInsert: true)
          .withConverter<Map<String, dynamic>>(
              $CollectionsTable.$convertermetadata);
  static const VerificationMeta _createdMeta =
      const VerificationMeta('created');
  @override
  late final GeneratedColumn<DateTime> created = GeneratedColumn<DateTime>(
      'created', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _updatedMeta =
      const VerificationMeta('updated');
  @override
  late final GeneratedColumn<DateTime> updated = GeneratedColumn<DateTime>(
      'updated', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
      'type', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('base'));
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _systemMeta = const VerificationMeta('system');
  @override
  late final GeneratedColumn<bool> system =
      GeneratedColumn<bool>('system', aliasedName, false,
          type: DriftSqlType.bool,
          requiredDuringInsert: false,
          defaultConstraints: GeneratedColumn.constraintsDependsOnDialect({
            SqlDialect.sqlite: 'CHECK ("system" IN (0, 1))',
            SqlDialect.mysql: '',
            SqlDialect.postgres: '',
          }),
          defaultValue: const Constant(false));
  static const VerificationMeta _listRuleMeta =
      const VerificationMeta('listRule');
  @override
  late final GeneratedColumn<String> listRule = GeneratedColumn<String>(
      'listRule', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _viewRuleMeta =
      const VerificationMeta('viewRule');
  @override
  late final GeneratedColumn<String> viewRule = GeneratedColumn<String>(
      'viewRule', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _createRuleMeta =
      const VerificationMeta('createRule');
  @override
  late final GeneratedColumn<String> createRule = GeneratedColumn<String>(
      'createRule', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _updateRuleMeta =
      const VerificationMeta('updateRule');
  @override
  late final GeneratedColumn<String> updateRule = GeneratedColumn<String>(
      'updateRule', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _deleteRuleMeta =
      const VerificationMeta('deleteRule');
  @override
  late final GeneratedColumn<String> deleteRule = GeneratedColumn<String>(
      'deleteRule', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _schemaMeta = const VerificationMeta('schema');
  @override
  late final GeneratedColumnWithTypeConverter<List<SchemaField>, String>
      schema = GeneratedColumn<String>('schema', aliasedName, false,
              type: DriftSqlType.string, requiredDuringInsert: true)
          .withConverter<List<SchemaField>>($CollectionsTable.$converterschema);
  static const VerificationMeta _indexesMeta =
      const VerificationMeta('indexes');
  @override
  late final GeneratedColumnWithTypeConverter<List<String>, String> indexes =
      GeneratedColumn<String>('indexes', aliasedName, false,
              type: DriftSqlType.string, requiredDuringInsert: true)
          .withConverter<List<String>>($CollectionsTable.$converterindexes);
  static const VerificationMeta _optionsMeta =
      const VerificationMeta('options');
  @override
  late final GeneratedColumnWithTypeConverter<Map<String, dynamic>, String>
      options = GeneratedColumn<String>('options', aliasedName, false,
              type: DriftSqlType.string, requiredDuringInsert: true)
          .withConverter<Map<String, dynamic>>(
              $CollectionsTable.$converteroptions);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        metadata,
        created,
        updated,
        type,
        name,
        system,
        listRule,
        viewRule,
        createRule,
        updateRule,
        deleteRule,
        schema,
        indexes,
        options
      ];
  @override
  String get aliasedName => _alias ?? 'Collections';
  @override
  String get actualTableName => 'Collections';
  @override
  VerificationContext validateIntegrity(Insertable<Collection> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    context.handle(_metadataMeta, const VerificationResult.success());
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
    if (data.containsKey('type')) {
      context.handle(
          _typeMeta, type.isAcceptableOrUnknown(data['type']!, _typeMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('system')) {
      context.handle(_systemMeta,
          system.isAcceptableOrUnknown(data['system']!, _systemMeta));
    }
    if (data.containsKey('listRule')) {
      context.handle(_listRuleMeta,
          listRule.isAcceptableOrUnknown(data['listRule']!, _listRuleMeta));
    }
    if (data.containsKey('viewRule')) {
      context.handle(_viewRuleMeta,
          viewRule.isAcceptableOrUnknown(data['viewRule']!, _viewRuleMeta));
    }
    if (data.containsKey('createRule')) {
      context.handle(
          _createRuleMeta,
          createRule.isAcceptableOrUnknown(
              data['createRule']!, _createRuleMeta));
    }
    if (data.containsKey('updateRule')) {
      context.handle(
          _updateRuleMeta,
          updateRule.isAcceptableOrUnknown(
              data['updateRule']!, _updateRuleMeta));
    }
    if (data.containsKey('deleteRule')) {
      context.handle(
          _deleteRuleMeta,
          deleteRule.isAcceptableOrUnknown(
              data['deleteRule']!, _deleteRuleMeta));
    }
    context.handle(_schemaMeta, const VerificationResult.success());
    context.handle(_indexesMeta, const VerificationResult.success());
    context.handle(_optionsMeta, const VerificationResult.success());
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Collection map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Collection(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      metadata: $CollectionsTable.$convertermetadata.fromSql(attachedDatabase
          .typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}metadata'])!),
      created: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created'])!,
      updated: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated'])!,
      type: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}type'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      system: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}system'])!,
      listRule: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}listRule']),
      viewRule: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}viewRule']),
      createRule: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}createRule']),
      updateRule: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}updateRule']),
      deleteRule: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}deleteRule']),
      schema: $CollectionsTable.$converterschema.fromSql(attachedDatabase
          .typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}schema'])!),
      indexes: $CollectionsTable.$converterindexes.fromSql(attachedDatabase
          .typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}indexes'])!),
      options: $CollectionsTable.$converteroptions.fromSql(attachedDatabase
          .typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}options'])!),
    );
  }

  @override
  $CollectionsTable createAlias(String alias) {
    return $CollectionsTable(attachedDatabase, alias);
  }

  static TypeConverter<Map<String, dynamic>, String> $convertermetadata =
      const JsonMapper();
  static TypeConverter<List<SchemaField>, String> $converterschema =
      const SchemaFieldListMapper();
  static TypeConverter<List<String>, String> $converterindexes =
      const StringListMapper();
  static TypeConverter<Map<String, dynamic>, String> $converteroptions =
      const JsonMapper();
}

class Collection extends ServiceRecord implements Insertable<Collection> {
  final String id;
  final Map<String, dynamic> metadata;
  final DateTime created;
  final DateTime updated;
  final String type;
  final String name;
  final bool system;
  final String? listRule;
  final String? viewRule;
  final String? createRule;
  final String? updateRule;
  final String? deleteRule;
  final List<SchemaField> schema;
  final List<String> indexes;
  final Map<String, dynamic> options;
  const Collection(
      {required this.id,
      required this.metadata,
      required this.created,
      required this.updated,
      required this.type,
      required this.name,
      required this.system,
      this.listRule,
      this.viewRule,
      this.createRule,
      this.updateRule,
      this.deleteRule,
      required this.schema,
      required this.indexes,
      required this.options});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    {
      final converter = $CollectionsTable.$convertermetadata;
      map['metadata'] = Variable<String>(converter.toSql(metadata));
    }
    map['created'] = Variable<DateTime>(created);
    map['updated'] = Variable<DateTime>(updated);
    map['type'] = Variable<String>(type);
    map['name'] = Variable<String>(name);
    map['system'] = Variable<bool>(system);
    if (!nullToAbsent || listRule != null) {
      map['listRule'] = Variable<String>(listRule);
    }
    if (!nullToAbsent || viewRule != null) {
      map['viewRule'] = Variable<String>(viewRule);
    }
    if (!nullToAbsent || createRule != null) {
      map['createRule'] = Variable<String>(createRule);
    }
    if (!nullToAbsent || updateRule != null) {
      map['updateRule'] = Variable<String>(updateRule);
    }
    if (!nullToAbsent || deleteRule != null) {
      map['deleteRule'] = Variable<String>(deleteRule);
    }
    {
      final converter = $CollectionsTable.$converterschema;
      map['schema'] = Variable<String>(converter.toSql(schema));
    }
    {
      final converter = $CollectionsTable.$converterindexes;
      map['indexes'] = Variable<String>(converter.toSql(indexes));
    }
    {
      final converter = $CollectionsTable.$converteroptions;
      map['options'] = Variable<String>(converter.toSql(options));
    }
    return map;
  }

  CollectionsCompanion toCompanion(bool nullToAbsent) {
    return CollectionsCompanion(
      id: Value(id),
      metadata: Value(metadata),
      created: Value(created),
      updated: Value(updated),
      type: Value(type),
      name: Value(name),
      system: Value(system),
      listRule: listRule == null && nullToAbsent
          ? const Value.absent()
          : Value(listRule),
      viewRule: viewRule == null && nullToAbsent
          ? const Value.absent()
          : Value(viewRule),
      createRule: createRule == null && nullToAbsent
          ? const Value.absent()
          : Value(createRule),
      updateRule: updateRule == null && nullToAbsent
          ? const Value.absent()
          : Value(updateRule),
      deleteRule: deleteRule == null && nullToAbsent
          ? const Value.absent()
          : Value(deleteRule),
      schema: Value(schema),
      indexes: Value(indexes),
      options: Value(options),
    );
  }

  factory Collection.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Collection(
      id: serializer.fromJson<String>(json['id']),
      metadata: serializer.fromJson<Map<String, dynamic>>(json['metadata']),
      created: serializer.fromJson<DateTime>(json['created']),
      updated: serializer.fromJson<DateTime>(json['updated']),
      type: serializer.fromJson<String>(json['type']),
      name: serializer.fromJson<String>(json['name']),
      system: serializer.fromJson<bool>(json['system']),
      listRule: serializer.fromJson<String?>(json['listRule']),
      viewRule: serializer.fromJson<String?>(json['viewRule']),
      createRule: serializer.fromJson<String?>(json['createRule']),
      updateRule: serializer.fromJson<String?>(json['updateRule']),
      deleteRule: serializer.fromJson<String?>(json['deleteRule']),
      schema: serializer.fromJson<List<SchemaField>>(json['schema']),
      indexes: serializer.fromJson<List<String>>(json['indexes']),
      options: serializer.fromJson<Map<String, dynamic>>(json['options']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'metadata': serializer.toJson<Map<String, dynamic>>(metadata),
      'created': serializer.toJson<DateTime>(created),
      'updated': serializer.toJson<DateTime>(updated),
      'type': serializer.toJson<String>(type),
      'name': serializer.toJson<String>(name),
      'system': serializer.toJson<bool>(system),
      'listRule': serializer.toJson<String?>(listRule),
      'viewRule': serializer.toJson<String?>(viewRule),
      'createRule': serializer.toJson<String?>(createRule),
      'updateRule': serializer.toJson<String?>(updateRule),
      'deleteRule': serializer.toJson<String?>(deleteRule),
      'schema': serializer.toJson<List<SchemaField>>(schema),
      'indexes': serializer.toJson<List<String>>(indexes),
      'options': serializer.toJson<Map<String, dynamic>>(options),
    };
  }

  Collection copyWith(
          {String? id,
          Map<String, dynamic>? metadata,
          DateTime? created,
          DateTime? updated,
          String? type,
          String? name,
          bool? system,
          Value<String?> listRule = const Value.absent(),
          Value<String?> viewRule = const Value.absent(),
          Value<String?> createRule = const Value.absent(),
          Value<String?> updateRule = const Value.absent(),
          Value<String?> deleteRule = const Value.absent(),
          List<SchemaField>? schema,
          List<String>? indexes,
          Map<String, dynamic>? options}) =>
      Collection(
        id: id ?? this.id,
        metadata: metadata ?? this.metadata,
        created: created ?? this.created,
        updated: updated ?? this.updated,
        type: type ?? this.type,
        name: name ?? this.name,
        system: system ?? this.system,
        listRule: listRule.present ? listRule.value : this.listRule,
        viewRule: viewRule.present ? viewRule.value : this.viewRule,
        createRule: createRule.present ? createRule.value : this.createRule,
        updateRule: updateRule.present ? updateRule.value : this.updateRule,
        deleteRule: deleteRule.present ? deleteRule.value : this.deleteRule,
        schema: schema ?? this.schema,
        indexes: indexes ?? this.indexes,
        options: options ?? this.options,
      );
  @override
  String toString() {
    return (StringBuffer('Collection(')
          ..write('id: $id, ')
          ..write('metadata: $metadata, ')
          ..write('created: $created, ')
          ..write('updated: $updated, ')
          ..write('type: $type, ')
          ..write('name: $name, ')
          ..write('system: $system, ')
          ..write('listRule: $listRule, ')
          ..write('viewRule: $viewRule, ')
          ..write('createRule: $createRule, ')
          ..write('updateRule: $updateRule, ')
          ..write('deleteRule: $deleteRule, ')
          ..write('schema: $schema, ')
          ..write('indexes: $indexes, ')
          ..write('options: $options')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      metadata,
      created,
      updated,
      type,
      name,
      system,
      listRule,
      viewRule,
      createRule,
      updateRule,
      deleteRule,
      schema,
      indexes,
      options);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Collection &&
          other.id == this.id &&
          other.metadata == this.metadata &&
          other.created == this.created &&
          other.updated == this.updated &&
          other.type == this.type &&
          other.name == this.name &&
          other.system == this.system &&
          other.listRule == this.listRule &&
          other.viewRule == this.viewRule &&
          other.createRule == this.createRule &&
          other.updateRule == this.updateRule &&
          other.deleteRule == this.deleteRule &&
          other.schema == this.schema &&
          other.indexes == this.indexes &&
          other.options == this.options);
}

class CollectionsCompanion extends UpdateCompanion<Collection> {
  final Value<String> id;
  final Value<Map<String, dynamic>> metadata;
  final Value<DateTime> created;
  final Value<DateTime> updated;
  final Value<String> type;
  final Value<String> name;
  final Value<bool> system;
  final Value<String?> listRule;
  final Value<String?> viewRule;
  final Value<String?> createRule;
  final Value<String?> updateRule;
  final Value<String?> deleteRule;
  final Value<List<SchemaField>> schema;
  final Value<List<String>> indexes;
  final Value<Map<String, dynamic>> options;
  final Value<int> rowid;
  const CollectionsCompanion({
    this.id = const Value.absent(),
    this.metadata = const Value.absent(),
    this.created = const Value.absent(),
    this.updated = const Value.absent(),
    this.type = const Value.absent(),
    this.name = const Value.absent(),
    this.system = const Value.absent(),
    this.listRule = const Value.absent(),
    this.viewRule = const Value.absent(),
    this.createRule = const Value.absent(),
    this.updateRule = const Value.absent(),
    this.deleteRule = const Value.absent(),
    this.schema = const Value.absent(),
    this.indexes = const Value.absent(),
    this.options = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CollectionsCompanion.insert({
    this.id = const Value.absent(),
    required Map<String, dynamic> metadata,
    required DateTime created,
    required DateTime updated,
    this.type = const Value.absent(),
    required String name,
    this.system = const Value.absent(),
    this.listRule = const Value.absent(),
    this.viewRule = const Value.absent(),
    this.createRule = const Value.absent(),
    this.updateRule = const Value.absent(),
    this.deleteRule = const Value.absent(),
    required List<SchemaField> schema,
    required List<String> indexes,
    required Map<String, dynamic> options,
    this.rowid = const Value.absent(),
  })  : metadata = Value(metadata),
        created = Value(created),
        updated = Value(updated),
        name = Value(name),
        schema = Value(schema),
        indexes = Value(indexes),
        options = Value(options);
  static Insertable<Collection> custom({
    Expression<String>? id,
    Expression<String>? metadata,
    Expression<DateTime>? created,
    Expression<DateTime>? updated,
    Expression<String>? type,
    Expression<String>? name,
    Expression<bool>? system,
    Expression<String>? listRule,
    Expression<String>? viewRule,
    Expression<String>? createRule,
    Expression<String>? updateRule,
    Expression<String>? deleteRule,
    Expression<String>? schema,
    Expression<String>? indexes,
    Expression<String>? options,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (metadata != null) 'metadata': metadata,
      if (created != null) 'created': created,
      if (updated != null) 'updated': updated,
      if (type != null) 'type': type,
      if (name != null) 'name': name,
      if (system != null) 'system': system,
      if (listRule != null) 'listRule': listRule,
      if (viewRule != null) 'viewRule': viewRule,
      if (createRule != null) 'createRule': createRule,
      if (updateRule != null) 'updateRule': updateRule,
      if (deleteRule != null) 'deleteRule': deleteRule,
      if (schema != null) 'schema': schema,
      if (indexes != null) 'indexes': indexes,
      if (options != null) 'options': options,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CollectionsCompanion copyWith(
      {Value<String>? id,
      Value<Map<String, dynamic>>? metadata,
      Value<DateTime>? created,
      Value<DateTime>? updated,
      Value<String>? type,
      Value<String>? name,
      Value<bool>? system,
      Value<String?>? listRule,
      Value<String?>? viewRule,
      Value<String?>? createRule,
      Value<String?>? updateRule,
      Value<String?>? deleteRule,
      Value<List<SchemaField>>? schema,
      Value<List<String>>? indexes,
      Value<Map<String, dynamic>>? options,
      Value<int>? rowid}) {
    return CollectionsCompanion(
      id: id ?? this.id,
      metadata: metadata ?? this.metadata,
      created: created ?? this.created,
      updated: updated ?? this.updated,
      type: type ?? this.type,
      name: name ?? this.name,
      system: system ?? this.system,
      listRule: listRule ?? this.listRule,
      viewRule: viewRule ?? this.viewRule,
      createRule: createRule ?? this.createRule,
      updateRule: updateRule ?? this.updateRule,
      deleteRule: deleteRule ?? this.deleteRule,
      schema: schema ?? this.schema,
      indexes: indexes ?? this.indexes,
      options: options ?? this.options,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (metadata.present) {
      final converter = $CollectionsTable.$convertermetadata;
      map['metadata'] = Variable<String>(converter.toSql(metadata.value));
    }
    if (created.present) {
      map['created'] = Variable<DateTime>(created.value);
    }
    if (updated.present) {
      map['updated'] = Variable<DateTime>(updated.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (system.present) {
      map['system'] = Variable<bool>(system.value);
    }
    if (listRule.present) {
      map['listRule'] = Variable<String>(listRule.value);
    }
    if (viewRule.present) {
      map['viewRule'] = Variable<String>(viewRule.value);
    }
    if (createRule.present) {
      map['createRule'] = Variable<String>(createRule.value);
    }
    if (updateRule.present) {
      map['updateRule'] = Variable<String>(updateRule.value);
    }
    if (deleteRule.present) {
      map['deleteRule'] = Variable<String>(deleteRule.value);
    }
    if (schema.present) {
      final converter = $CollectionsTable.$converterschema;
      map['schema'] = Variable<String>(converter.toSql(schema.value));
    }
    if (indexes.present) {
      final converter = $CollectionsTable.$converterindexes;
      map['indexes'] = Variable<String>(converter.toSql(indexes.value));
    }
    if (options.present) {
      final converter = $CollectionsTable.$converteroptions;
      map['options'] = Variable<String>(converter.toSql(options.value));
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CollectionsCompanion(')
          ..write('id: $id, ')
          ..write('metadata: $metadata, ')
          ..write('created: $created, ')
          ..write('updated: $updated, ')
          ..write('type: $type, ')
          ..write('name: $name, ')
          ..write('system: $system, ')
          ..write('listRule: $listRule, ')
          ..write('viewRule: $viewRule, ')
          ..write('createRule: $createRule, ')
          ..write('updateRule: $updateRule, ')
          ..write('deleteRule: $deleteRule, ')
          ..write('schema: $schema, ')
          ..write('indexes: $indexes, ')
          ..write('options: $options, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RecordsTable extends Records with TableInfo<$RecordsTable, Record> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      clientDefault: newId);
  static const VerificationMeta _metadataMeta =
      const VerificationMeta('metadata');
  @override
  late final GeneratedColumnWithTypeConverter<Map<String, dynamic>, String>
      metadata = GeneratedColumn<String>('metadata', aliasedName, false,
              type: DriftSqlType.string, requiredDuringInsert: true)
          .withConverter<Map<String, dynamic>>(
              $RecordsTable.$convertermetadata);
  static const VerificationMeta _createdMeta =
      const VerificationMeta('created');
  @override
  late final GeneratedColumn<DateTime> created = GeneratedColumn<DateTime>(
      'created', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _updatedMeta =
      const VerificationMeta('updated');
  @override
  late final GeneratedColumn<DateTime> updated = GeneratedColumn<DateTime>(
      'updated', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _dataMeta = const VerificationMeta('data');
  @override
  late final GeneratedColumnWithTypeConverter<Map<String, dynamic>, String>
      data = GeneratedColumn<String>('data', aliasedName, false,
              type: DriftSqlType.string, requiredDuringInsert: true)
          .withConverter<Map<String, dynamic>>($RecordsTable.$converterdata);
  static const VerificationMeta _collectionIdMeta =
      const VerificationMeta('collectionId');
  @override
  late final GeneratedColumn<String> collectionId = GeneratedColumn<String>(
      'collectionId', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('REFERENCES Collections (id)'));
  static const VerificationMeta _collectionNameMeta =
      const VerificationMeta('collectionName');
  @override
  late final GeneratedColumn<String> collectionName = GeneratedColumn<String>(
      'collectionName', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('REFERENCES Collections (name)'));
  @override
  List<GeneratedColumn> get $columns =>
      [id, metadata, created, updated, data, collectionId, collectionName];
  @override
  String get aliasedName => _alias ?? 'Records';
  @override
  String get actualTableName => 'Records';
  @override
  VerificationContext validateIntegrity(Insertable<Record> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    context.handle(_metadataMeta, const VerificationResult.success());
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
    context.handle(_dataMeta, const VerificationResult.success());
    if (data.containsKey('collectionId')) {
      context.handle(
          _collectionIdMeta,
          collectionId.isAcceptableOrUnknown(
              data['collectionId']!, _collectionIdMeta));
    } else if (isInserting) {
      context.missing(_collectionIdMeta);
    }
    if (data.containsKey('collectionName')) {
      context.handle(
          _collectionNameMeta,
          collectionName.isAcceptableOrUnknown(
              data['collectionName']!, _collectionNameMeta));
    } else if (isInserting) {
      context.missing(_collectionNameMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id, collectionId};
  @override
  Record map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Record(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      metadata: $RecordsTable.$convertermetadata.fromSql(attachedDatabase
          .typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}metadata'])!),
      created: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created'])!,
      updated: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated'])!,
      data: $RecordsTable.$converterdata.fromSql(attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}data'])!),
      collectionId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}collectionId'])!,
      collectionName: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}collectionName'])!,
    );
  }

  @override
  $RecordsTable createAlias(String alias) {
    return $RecordsTable(attachedDatabase, alias);
  }

  static TypeConverter<Map<String, dynamic>, String> $convertermetadata =
      const JsonMapper();
  static TypeConverter<Map<String, dynamic>, String> $converterdata =
      const JsonMapper();
}

class Record extends ServiceRecord implements Insertable<Record> {
  final String id;
  final Map<String, dynamic> metadata;
  final DateTime created;
  final DateTime updated;
  final Map<String, dynamic> data;
  final String collectionId;
  final String collectionName;
  const Record(
      {required this.id,
      required this.metadata,
      required this.created,
      required this.updated,
      required this.data,
      required this.collectionId,
      required this.collectionName});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    {
      final converter = $RecordsTable.$convertermetadata;
      map['metadata'] = Variable<String>(converter.toSql(metadata));
    }
    map['created'] = Variable<DateTime>(created);
    map['updated'] = Variable<DateTime>(updated);
    {
      final converter = $RecordsTable.$converterdata;
      map['data'] = Variable<String>(converter.toSql(data));
    }
    map['collectionId'] = Variable<String>(collectionId);
    map['collectionName'] = Variable<String>(collectionName);
    return map;
  }

  RecordsCompanion toCompanion(bool nullToAbsent) {
    return RecordsCompanion(
      id: Value(id),
      metadata: Value(metadata),
      created: Value(created),
      updated: Value(updated),
      data: Value(data),
      collectionId: Value(collectionId),
      collectionName: Value(collectionName),
    );
  }

  factory Record.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Record(
      id: serializer.fromJson<String>(json['id']),
      metadata: serializer.fromJson<Map<String, dynamic>>(json['metadata']),
      created: serializer.fromJson<DateTime>(json['created']),
      updated: serializer.fromJson<DateTime>(json['updated']),
      data: serializer.fromJson<Map<String, dynamic>>(json['data']),
      collectionId: serializer.fromJson<String>(json['collectionId']),
      collectionName: serializer.fromJson<String>(json['collectionName']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'metadata': serializer.toJson<Map<String, dynamic>>(metadata),
      'created': serializer.toJson<DateTime>(created),
      'updated': serializer.toJson<DateTime>(updated),
      'data': serializer.toJson<Map<String, dynamic>>(data),
      'collectionId': serializer.toJson<String>(collectionId),
      'collectionName': serializer.toJson<String>(collectionName),
    };
  }

  Record copyWith(
          {String? id,
          Map<String, dynamic>? metadata,
          DateTime? created,
          DateTime? updated,
          Map<String, dynamic>? data,
          String? collectionId,
          String? collectionName}) =>
      Record(
        id: id ?? this.id,
        metadata: metadata ?? this.metadata,
        created: created ?? this.created,
        updated: updated ?? this.updated,
        data: data ?? this.data,
        collectionId: collectionId ?? this.collectionId,
        collectionName: collectionName ?? this.collectionName,
      );
  @override
  String toString() {
    return (StringBuffer('Record(')
          ..write('id: $id, ')
          ..write('metadata: $metadata, ')
          ..write('created: $created, ')
          ..write('updated: $updated, ')
          ..write('data: $data, ')
          ..write('collectionId: $collectionId, ')
          ..write('collectionName: $collectionName')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id, metadata, created, updated, data, collectionId, collectionName);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Record &&
          other.id == this.id &&
          other.metadata == this.metadata &&
          other.created == this.created &&
          other.updated == this.updated &&
          other.data == this.data &&
          other.collectionId == this.collectionId &&
          other.collectionName == this.collectionName);
}

class RecordsCompanion extends UpdateCompanion<Record> {
  final Value<String> id;
  final Value<Map<String, dynamic>> metadata;
  final Value<DateTime> created;
  final Value<DateTime> updated;
  final Value<Map<String, dynamic>> data;
  final Value<String> collectionId;
  final Value<String> collectionName;
  final Value<int> rowid;
  const RecordsCompanion({
    this.id = const Value.absent(),
    this.metadata = const Value.absent(),
    this.created = const Value.absent(),
    this.updated = const Value.absent(),
    this.data = const Value.absent(),
    this.collectionId = const Value.absent(),
    this.collectionName = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RecordsCompanion.insert({
    this.id = const Value.absent(),
    required Map<String, dynamic> metadata,
    required DateTime created,
    required DateTime updated,
    required Map<String, dynamic> data,
    required String collectionId,
    required String collectionName,
    this.rowid = const Value.absent(),
  })  : metadata = Value(metadata),
        created = Value(created),
        updated = Value(updated),
        data = Value(data),
        collectionId = Value(collectionId),
        collectionName = Value(collectionName);
  static Insertable<Record> custom({
    Expression<String>? id,
    Expression<String>? metadata,
    Expression<DateTime>? created,
    Expression<DateTime>? updated,
    Expression<String>? data,
    Expression<String>? collectionId,
    Expression<String>? collectionName,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (metadata != null) 'metadata': metadata,
      if (created != null) 'created': created,
      if (updated != null) 'updated': updated,
      if (data != null) 'data': data,
      if (collectionId != null) 'collectionId': collectionId,
      if (collectionName != null) 'collectionName': collectionName,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RecordsCompanion copyWith(
      {Value<String>? id,
      Value<Map<String, dynamic>>? metadata,
      Value<DateTime>? created,
      Value<DateTime>? updated,
      Value<Map<String, dynamic>>? data,
      Value<String>? collectionId,
      Value<String>? collectionName,
      Value<int>? rowid}) {
    return RecordsCompanion(
      id: id ?? this.id,
      metadata: metadata ?? this.metadata,
      created: created ?? this.created,
      updated: updated ?? this.updated,
      data: data ?? this.data,
      collectionId: collectionId ?? this.collectionId,
      collectionName: collectionName ?? this.collectionName,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (metadata.present) {
      final converter = $RecordsTable.$convertermetadata;
      map['metadata'] = Variable<String>(converter.toSql(metadata.value));
    }
    if (created.present) {
      map['created'] = Variable<DateTime>(created.value);
    }
    if (updated.present) {
      map['updated'] = Variable<DateTime>(updated.value);
    }
    if (data.present) {
      final converter = $RecordsTable.$converterdata;
      map['data'] = Variable<String>(converter.toSql(data.value));
    }
    if (collectionId.present) {
      map['collectionId'] = Variable<String>(collectionId.value);
    }
    if (collectionName.present) {
      map['collectionName'] = Variable<String>(collectionName.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RecordsCompanion(')
          ..write('id: $id, ')
          ..write('metadata: $metadata, ')
          ..write('created: $created, ')
          ..write('updated: $updated, ')
          ..write('data: $data, ')
          ..write('collectionId: $collectionId, ')
          ..write('collectionName: $collectionName, ')
          ..write('rowid: $rowid')
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
  static const VerificationMeta _dataMeta = const VerificationMeta('data');
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
  Set<GeneratedColumn> get $primaryKey => const {};
  @override
  TextEntrie map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TextEntrie(
      data: attachedDatabase.typeMapping
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
  String get moduleAndArgs =>
      'fts5(data, content=records, content_rowid=rowid)';
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
  final Value<int> rowid;
  const TextEntriesCompanion({
    this.data = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TextEntriesCompanion.insert({
    required String data,
    this.rowid = const Value.absent(),
  }) : data = Value(data);
  static Insertable<TextEntrie> custom({
    Expression<String>? data,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (data != null) 'data': data,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TextEntriesCompanion copyWith({Value<String>? data, Value<int>? rowid}) {
    return TextEntriesCompanion(
      data: data ?? this.data,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (data.present) {
      map['data'] = Variable<String>(data.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TextEntriesCompanion(')
          ..write('data: $data, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AdminsTable extends Admins with TableInfo<$AdminsTable, Admin> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AdminsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      clientDefault: newId);
  static const VerificationMeta _metadataMeta =
      const VerificationMeta('metadata');
  @override
  late final GeneratedColumnWithTypeConverter<Map<String, dynamic>, String>
      metadata = GeneratedColumn<String>('metadata', aliasedName, false,
              type: DriftSqlType.string, requiredDuringInsert: true)
          .withConverter<Map<String, dynamic>>($AdminsTable.$convertermetadata);
  static const VerificationMeta _createdMeta =
      const VerificationMeta('created');
  @override
  late final GeneratedColumn<DateTime> created = GeneratedColumn<DateTime>(
      'created', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _updatedMeta =
      const VerificationMeta('updated');
  @override
  late final GeneratedColumn<DateTime> updated = GeneratedColumn<DateTime>(
      'updated', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _emailMeta = const VerificationMeta('email');
  @override
  late final GeneratedColumn<String> email = GeneratedColumn<String>(
      'email', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _avatarMeta = const VerificationMeta('avatar');
  @override
  late final GeneratedColumn<int> avatar = GeneratedColumn<int>(
      'avatar', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  @override
  List<GeneratedColumn> get $columns =>
      [id, metadata, created, updated, email, avatar];
  @override
  String get aliasedName => _alias ?? 'Admins';
  @override
  String get actualTableName => 'Admins';
  @override
  VerificationContext validateIntegrity(Insertable<Admin> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    context.handle(_metadataMeta, const VerificationResult.success());
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
    if (data.containsKey('email')) {
      context.handle(
          _emailMeta, email.isAcceptableOrUnknown(data['email']!, _emailMeta));
    } else if (isInserting) {
      context.missing(_emailMeta);
    }
    if (data.containsKey('avatar')) {
      context.handle(_avatarMeta,
          avatar.isAcceptableOrUnknown(data['avatar']!, _avatarMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Admin map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Admin(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      metadata: $AdminsTable.$convertermetadata.fromSql(attachedDatabase
          .typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}metadata'])!),
      created: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created'])!,
      updated: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated'])!,
      email: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}email'])!,
      avatar: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}avatar'])!,
    );
  }

  @override
  $AdminsTable createAlias(String alias) {
    return $AdminsTable(attachedDatabase, alias);
  }

  static TypeConverter<Map<String, dynamic>, String> $convertermetadata =
      const JsonMapper();
}

class Admin extends ServiceRecord implements Insertable<Admin> {
  final String id;
  final Map<String, dynamic> metadata;
  final DateTime created;
  final DateTime updated;
  final String email;
  final int avatar;
  const Admin(
      {required this.id,
      required this.metadata,
      required this.created,
      required this.updated,
      required this.email,
      required this.avatar});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    {
      final converter = $AdminsTable.$convertermetadata;
      map['metadata'] = Variable<String>(converter.toSql(metadata));
    }
    map['created'] = Variable<DateTime>(created);
    map['updated'] = Variable<DateTime>(updated);
    map['email'] = Variable<String>(email);
    map['avatar'] = Variable<int>(avatar);
    return map;
  }

  AdminsCompanion toCompanion(bool nullToAbsent) {
    return AdminsCompanion(
      id: Value(id),
      metadata: Value(metadata),
      created: Value(created),
      updated: Value(updated),
      email: Value(email),
      avatar: Value(avatar),
    );
  }

  factory Admin.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Admin(
      id: serializer.fromJson<String>(json['id']),
      metadata: serializer.fromJson<Map<String, dynamic>>(json['metadata']),
      created: serializer.fromJson<DateTime>(json['created']),
      updated: serializer.fromJson<DateTime>(json['updated']),
      email: serializer.fromJson<String>(json['email']),
      avatar: serializer.fromJson<int>(json['avatar']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'metadata': serializer.toJson<Map<String, dynamic>>(metadata),
      'created': serializer.toJson<DateTime>(created),
      'updated': serializer.toJson<DateTime>(updated),
      'email': serializer.toJson<String>(email),
      'avatar': serializer.toJson<int>(avatar),
    };
  }

  Admin copyWith(
          {String? id,
          Map<String, dynamic>? metadata,
          DateTime? created,
          DateTime? updated,
          String? email,
          int? avatar}) =>
      Admin(
        id: id ?? this.id,
        metadata: metadata ?? this.metadata,
        created: created ?? this.created,
        updated: updated ?? this.updated,
        email: email ?? this.email,
        avatar: avatar ?? this.avatar,
      );
  @override
  String toString() {
    return (StringBuffer('Admin(')
          ..write('id: $id, ')
          ..write('metadata: $metadata, ')
          ..write('created: $created, ')
          ..write('updated: $updated, ')
          ..write('email: $email, ')
          ..write('avatar: $avatar')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, metadata, created, updated, email, avatar);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Admin &&
          other.id == this.id &&
          other.metadata == this.metadata &&
          other.created == this.created &&
          other.updated == this.updated &&
          other.email == this.email &&
          other.avatar == this.avatar);
}

class AdminsCompanion extends UpdateCompanion<Admin> {
  final Value<String> id;
  final Value<Map<String, dynamic>> metadata;
  final Value<DateTime> created;
  final Value<DateTime> updated;
  final Value<String> email;
  final Value<int> avatar;
  final Value<int> rowid;
  const AdminsCompanion({
    this.id = const Value.absent(),
    this.metadata = const Value.absent(),
    this.created = const Value.absent(),
    this.updated = const Value.absent(),
    this.email = const Value.absent(),
    this.avatar = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AdminsCompanion.insert({
    this.id = const Value.absent(),
    required Map<String, dynamic> metadata,
    required DateTime created,
    required DateTime updated,
    required String email,
    this.avatar = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : metadata = Value(metadata),
        created = Value(created),
        updated = Value(updated),
        email = Value(email);
  static Insertable<Admin> custom({
    Expression<String>? id,
    Expression<String>? metadata,
    Expression<DateTime>? created,
    Expression<DateTime>? updated,
    Expression<String>? email,
    Expression<int>? avatar,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (metadata != null) 'metadata': metadata,
      if (created != null) 'created': created,
      if (updated != null) 'updated': updated,
      if (email != null) 'email': email,
      if (avatar != null) 'avatar': avatar,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AdminsCompanion copyWith(
      {Value<String>? id,
      Value<Map<String, dynamic>>? metadata,
      Value<DateTime>? created,
      Value<DateTime>? updated,
      Value<String>? email,
      Value<int>? avatar,
      Value<int>? rowid}) {
    return AdminsCompanion(
      id: id ?? this.id,
      metadata: metadata ?? this.metadata,
      created: created ?? this.created,
      updated: updated ?? this.updated,
      email: email ?? this.email,
      avatar: avatar ?? this.avatar,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (metadata.present) {
      final converter = $AdminsTable.$convertermetadata;
      map['metadata'] = Variable<String>(converter.toSql(metadata.value));
    }
    if (created.present) {
      map['created'] = Variable<DateTime>(created.value);
    }
    if (updated.present) {
      map['updated'] = Variable<DateTime>(updated.value);
    }
    if (email.present) {
      map['email'] = Variable<String>(email.value);
    }
    if (avatar.present) {
      map['avatar'] = Variable<int>(avatar.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AdminsCompanion(')
          ..write('id: $id, ')
          ..write('metadata: $metadata, ')
          ..write('created: $created, ')
          ..write('updated: $updated, ')
          ..write('email: $email, ')
          ..write('avatar: $avatar, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AuthTokensTable extends AuthTokens
    with TableInfo<$AuthTokensTable, AuthToken> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AuthTokensTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _tokenMeta = const VerificationMeta('token');
  @override
  late final GeneratedColumn<String> token = GeneratedColumn<String>(
      'token', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _createdMeta =
      const VerificationMeta('created');
  @override
  late final GeneratedColumn<DateTime> created = GeneratedColumn<DateTime>(
      'created', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [id, token, created];
  @override
  String get aliasedName => _alias ?? 'AuthTokens';
  @override
  String get actualTableName => 'AuthTokens';
  @override
  VerificationContext validateIntegrity(Insertable<AuthToken> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('token')) {
      context.handle(
          _tokenMeta, token.isAcceptableOrUnknown(data['token']!, _tokenMeta));
    } else if (isInserting) {
      context.missing(_tokenMeta);
    }
    if (data.containsKey('created')) {
      context.handle(_createdMeta,
          created.isAcceptableOrUnknown(data['created']!, _createdMeta));
    } else if (isInserting) {
      context.missing(_createdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AuthToken map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AuthToken(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      token: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}token'])!,
      created: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created'])!,
    );
  }

  @override
  $AuthTokensTable createAlias(String alias) {
    return $AuthTokensTable(attachedDatabase, alias);
  }
}

class AuthToken extends DataClass implements Insertable<AuthToken> {
  final int id;
  final String token;
  final DateTime created;
  const AuthToken(
      {required this.id, required this.token, required this.created});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['token'] = Variable<String>(token);
    map['created'] = Variable<DateTime>(created);
    return map;
  }

  AuthTokensCompanion toCompanion(bool nullToAbsent) {
    return AuthTokensCompanion(
      id: Value(id),
      token: Value(token),
      created: Value(created),
    );
  }

  factory AuthToken.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AuthToken(
      id: serializer.fromJson<int>(json['id']),
      token: serializer.fromJson<String>(json['token']),
      created: serializer.fromJson<DateTime>(json['created']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'token': serializer.toJson<String>(token),
      'created': serializer.toJson<DateTime>(created),
    };
  }

  AuthToken copyWith({int? id, String? token, DateTime? created}) => AuthToken(
        id: id ?? this.id,
        token: token ?? this.token,
        created: created ?? this.created,
      );
  @override
  String toString() {
    return (StringBuffer('AuthToken(')
          ..write('id: $id, ')
          ..write('token: $token, ')
          ..write('created: $created')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, token, created);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AuthToken &&
          other.id == this.id &&
          other.token == this.token &&
          other.created == this.created);
}

class AuthTokensCompanion extends UpdateCompanion<AuthToken> {
  final Value<int> id;
  final Value<String> token;
  final Value<DateTime> created;
  const AuthTokensCompanion({
    this.id = const Value.absent(),
    this.token = const Value.absent(),
    this.created = const Value.absent(),
  });
  AuthTokensCompanion.insert({
    this.id = const Value.absent(),
    required String token,
    required DateTime created,
  })  : token = Value(token),
        created = Value(created);
  static Insertable<AuthToken> custom({
    Expression<int>? id,
    Expression<String>? token,
    Expression<DateTime>? created,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (token != null) 'token': token,
      if (created != null) 'created': created,
    });
  }

  AuthTokensCompanion copyWith(
      {Value<int>? id, Value<String>? token, Value<DateTime>? created}) {
    return AuthTokensCompanion(
      id: id ?? this.id,
      token: token ?? this.token,
      created: created ?? this.created,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (token.present) {
      map['token'] = Variable<String>(token.value);
    }
    if (created.present) {
      map['created'] = Variable<DateTime>(created.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AuthTokensCompanion(')
          ..write('id: $id, ')
          ..write('token: $token, ')
          ..write('created: $created')
          ..write(')'))
        .toString();
  }
}

abstract class _$DataBase extends GeneratedDatabase {
  _$DataBase(QueryExecutor e) : super(e);
  _$DataBase.connect(DatabaseConnection c) : super.connect(c);
  late final $CollectionsTable collections = $CollectionsTable(this);
  late final $RecordsTable records = $RecordsTable(this);
  late final TextEntries textEntries = TextEntries(this);
  late final Trigger recordsInsert = Trigger(
      'CREATE TRIGGER records_insert AFTER INSERT ON records BEGIN INSERT INTO text_entries ("rowid", data) VALUES (new."rowid", new.data);END',
      'records_insert');
  late final Trigger recordsDelete = Trigger(
      'CREATE TRIGGER records_delete AFTER DELETE ON records BEGIN INSERT INTO text_entries (text_entries, "rowid", data) VALUES (\'delete\', old."rowid", old.data);END',
      'records_delete');
  late final Trigger recordsUpdate = Trigger(
      'CREATE TRIGGER records_update AFTER UPDATE ON records BEGIN INSERT INTO text_entries (text_entries, "rowid", data) VALUES (\'delete\', new."rowid", new.data);INSERT INTO text_entries ("rowid", data) VALUES (new."rowid", new.data);END',
      'records_update');
  late final $AdminsTable admins = $AdminsTable(this);
  late final $AuthTokensTable authTokens = $AuthTokensTable(this);
  late final RecordsDao recordsDao = RecordsDao(this as DataBase);
  late final CollectionsDao collectionsDao = CollectionsDao(this as DataBase);
  late final AdminsDao adminsDao = AdminsDao(this as DataBase);
  Selectable<SearchResult> _search(String query) {
    return customSelect(
        'SELECT"r"."id" AS "nested_0.id", "r"."metadata" AS "nested_0.metadata", "r"."created" AS "nested_0.created", "r"."updated" AS "nested_0.updated", "r"."data" AS "nested_0.data", "r"."collectionId" AS "nested_0.collectionId", "r"."collectionName" AS "nested_0.collectionName" FROM text_entries INNER JOIN records AS r ON r."rowid" = text_entries."rowid" WHERE text_entries MATCH ?1 ORDER BY rank',
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
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
        collections,
        records,
        textEntries,
        recordsInsert,
        recordsDelete,
        recordsUpdate,
        admins,
        authTokens
      ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules(
        [
          WritePropagation(
            on: TableUpdateQuery.onTableName('Records',
                limitUpdateKind: UpdateKind.insert),
            result: [
              TableUpdate('text_entries', kind: UpdateKind.insert),
            ],
          ),
          WritePropagation(
            on: TableUpdateQuery.onTableName('Records',
                limitUpdateKind: UpdateKind.delete),
            result: [
              TableUpdate('text_entries', kind: UpdateKind.insert),
            ],
          ),
          WritePropagation(
            on: TableUpdateQuery.onTableName('Records',
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
