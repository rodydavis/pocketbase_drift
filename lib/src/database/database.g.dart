// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $ServicesTable extends Services with TableInfo<$ServicesTable, Service> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ServicesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      clientDefault: newId);
  @override
  late final GeneratedColumnWithTypeConverter<Map<String, dynamic>, String>
      data = GeneratedColumn<String>('data', aliasedName, false,
              type: DriftSqlType.string, requiredDuringInsert: true)
          .withConverter<Map<String, dynamic>>($ServicesTable.$converterdata);
  static const VerificationMeta _serviceMeta =
      const VerificationMeta('service');
  @override
  late final GeneratedColumn<String> service = GeneratedColumn<String>(
      'service', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _createdMeta =
      const VerificationMeta('created');
  @override
  late final GeneratedColumn<String> created = GeneratedColumn<String>(
      'created', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _updatedMeta =
      const VerificationMeta('updated');
  @override
  late final GeneratedColumn<String> updated = GeneratedColumn<String>(
      'updated', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [id, data, service, created, updated];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'Services';
  @override
  VerificationContext validateIntegrity(Insertable<Service> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('service')) {
      context.handle(_serviceMeta,
          service.isAcceptableOrUnknown(data['service']!, _serviceMeta));
    } else if (isInserting) {
      context.missing(_serviceMeta);
    }
    if (data.containsKey('created')) {
      context.handle(_createdMeta,
          created.isAcceptableOrUnknown(data['created']!, _createdMeta));
    }
    if (data.containsKey('updated')) {
      context.handle(_updatedMeta,
          updated.isAcceptableOrUnknown(data['updated']!, _updatedMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id, service};
  @override
  Service map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Service(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      data: $ServicesTable.$converterdata.fromSql(attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}data'])!),
      service: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}service'])!,
      created: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}created']),
      updated: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}updated']),
    );
  }

  @override
  $ServicesTable createAlias(String alias) {
    return $ServicesTable(attachedDatabase, alias);
  }

  static TypeConverter<Map<String, dynamic>, String> $converterdata =
      const JsonMapper();
}

class Service extends DataClass implements Insertable<Service> {
  final String id;
  final Map<String, dynamic> data;
  final String service;
  final String? created;
  final String? updated;
  const Service(
      {required this.id,
      required this.data,
      required this.service,
      this.created,
      this.updated});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    {
      map['data'] = Variable<String>($ServicesTable.$converterdata.toSql(data));
    }
    map['service'] = Variable<String>(service);
    if (!nullToAbsent || created != null) {
      map['created'] = Variable<String>(created);
    }
    if (!nullToAbsent || updated != null) {
      map['updated'] = Variable<String>(updated);
    }
    return map;
  }

  ServicesCompanion toCompanion(bool nullToAbsent) {
    return ServicesCompanion(
      id: Value(id),
      data: Value(data),
      service: Value(service),
      created: created == null && nullToAbsent
          ? const Value.absent()
          : Value(created),
      updated: updated == null && nullToAbsent
          ? const Value.absent()
          : Value(updated),
    );
  }

  factory Service.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Service(
      id: serializer.fromJson<String>(json['id']),
      data: serializer.fromJson<Map<String, dynamic>>(json['data']),
      service: serializer.fromJson<String>(json['service']),
      created: serializer.fromJson<String?>(json['created']),
      updated: serializer.fromJson<String?>(json['updated']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'data': serializer.toJson<Map<String, dynamic>>(data),
      'service': serializer.toJson<String>(service),
      'created': serializer.toJson<String?>(created),
      'updated': serializer.toJson<String?>(updated),
    };
  }

  Service copyWith(
          {String? id,
          Map<String, dynamic>? data,
          String? service,
          Value<String?> created = const Value.absent(),
          Value<String?> updated = const Value.absent()}) =>
      Service(
        id: id ?? this.id,
        data: data ?? this.data,
        service: service ?? this.service,
        created: created.present ? created.value : this.created,
        updated: updated.present ? updated.value : this.updated,
      );
  Service copyWithCompanion(ServicesCompanion data) {
    return Service(
      id: data.id.present ? data.id.value : this.id,
      data: data.data.present ? data.data.value : this.data,
      service: data.service.present ? data.service.value : this.service,
      created: data.created.present ? data.created.value : this.created,
      updated: data.updated.present ? data.updated.value : this.updated,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Service(')
          ..write('id: $id, ')
          ..write('data: $data, ')
          ..write('service: $service, ')
          ..write('created: $created, ')
          ..write('updated: $updated')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, data, service, created, updated);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Service &&
          other.id == this.id &&
          other.data == this.data &&
          other.service == this.service &&
          other.created == this.created &&
          other.updated == this.updated);
}

class ServicesCompanion extends UpdateCompanion<Service> {
  final Value<String> id;
  final Value<Map<String, dynamic>> data;
  final Value<String> service;
  final Value<String?> created;
  final Value<String?> updated;
  final Value<int> rowid;
  const ServicesCompanion({
    this.id = const Value.absent(),
    this.data = const Value.absent(),
    this.service = const Value.absent(),
    this.created = const Value.absent(),
    this.updated = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ServicesCompanion.insert({
    this.id = const Value.absent(),
    required Map<String, dynamic> data,
    required String service,
    this.created = const Value.absent(),
    this.updated = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : data = Value(data),
        service = Value(service);
  static Insertable<Service> custom({
    Expression<String>? id,
    Expression<String>? data,
    Expression<String>? service,
    Expression<String>? created,
    Expression<String>? updated,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (data != null) 'data': data,
      if (service != null) 'service': service,
      if (created != null) 'created': created,
      if (updated != null) 'updated': updated,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ServicesCompanion copyWith(
      {Value<String>? id,
      Value<Map<String, dynamic>>? data,
      Value<String>? service,
      Value<String?>? created,
      Value<String?>? updated,
      Value<int>? rowid}) {
    return ServicesCompanion(
      id: id ?? this.id,
      data: data ?? this.data,
      service: service ?? this.service,
      created: created ?? this.created,
      updated: updated ?? this.updated,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (data.present) {
      map['data'] =
          Variable<String>($ServicesTable.$converterdata.toSql(data.value));
    }
    if (service.present) {
      map['service'] = Variable<String>(service.value);
    }
    if (created.present) {
      map['created'] = Variable<String>(created.value);
    }
    if (updated.present) {
      map['updated'] = Variable<String>(updated.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ServicesCompanion(')
          ..write('id: $id, ')
          ..write('data: $data, ')
          ..write('service: $service, ')
          ..write('created: $created, ')
          ..write('updated: $updated, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class TextEntries extends Table
    with
        TableInfo<TextEntries, TextEntry>,
        VirtualTableInfo<TextEntries, TextEntry> {
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
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'text_entries';
  @override
  VerificationContext validateIntegrity(Insertable<TextEntry> instance,
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
  TextEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TextEntry(
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
      'fts5(data, content=services, content_rowid=rowid)';
}

class TextEntry extends DataClass implements Insertable<TextEntry> {
  final String data;
  const TextEntry({required this.data});
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

  factory TextEntry.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TextEntry(
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

  TextEntry copyWith({String? data}) => TextEntry(
        data: data ?? this.data,
      );
  TextEntry copyWithCompanion(TextEntriesCompanion data) {
    return TextEntry(
      data: data.data.present ? data.data.value : this.data,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TextEntry(')
          ..write('data: $data')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => data.hashCode;
  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is TextEntry && other.data == this.data);
}

class TextEntriesCompanion extends UpdateCompanion<TextEntry> {
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
  static Insertable<TextEntry> custom({
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

class $BlobFilesTable extends BlobFiles
    with TableInfo<$BlobFilesTable, BlobFile> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BlobFilesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _recordIdMeta =
      const VerificationMeta('recordId');
  @override
  late final GeneratedColumn<String> recordId = GeneratedColumn<String>(
      'recordId', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('REFERENCES Services (id)'));
  static const VerificationMeta _filenameMeta =
      const VerificationMeta('filename');
  @override
  late final GeneratedColumn<String> filename = GeneratedColumn<String>(
      'filename', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _dataMeta = const VerificationMeta('data');
  @override
  late final GeneratedColumn<Uint8List> data = GeneratedColumn<Uint8List>(
      'data', aliasedName, false,
      type: DriftSqlType.blob, requiredDuringInsert: true);
  static const VerificationMeta _expirationMeta =
      const VerificationMeta('expiration');
  @override
  late final GeneratedColumn<DateTime> expiration = GeneratedColumn<DateTime>(
      'expiration', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _createdMeta =
      const VerificationMeta('created');
  @override
  late final GeneratedColumn<String> created = GeneratedColumn<String>(
      'created', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _updatedMeta =
      const VerificationMeta('updated');
  @override
  late final GeneratedColumn<String> updated = GeneratedColumn<String>(
      'updated', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns =>
      [id, recordId, filename, data, expiration, created, updated];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'BlobFiles';
  @override
  VerificationContext validateIntegrity(Insertable<BlobFile> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('recordId')) {
      context.handle(_recordIdMeta,
          recordId.isAcceptableOrUnknown(data['recordId']!, _recordIdMeta));
    } else if (isInserting) {
      context.missing(_recordIdMeta);
    }
    if (data.containsKey('filename')) {
      context.handle(_filenameMeta,
          filename.isAcceptableOrUnknown(data['filename']!, _filenameMeta));
    } else if (isInserting) {
      context.missing(_filenameMeta);
    }
    if (data.containsKey('data')) {
      context.handle(
          _dataMeta, this.data.isAcceptableOrUnknown(data['data']!, _dataMeta));
    } else if (isInserting) {
      context.missing(_dataMeta);
    }
    if (data.containsKey('expiration')) {
      context.handle(
          _expirationMeta,
          expiration.isAcceptableOrUnknown(
              data['expiration']!, _expirationMeta));
    }
    if (data.containsKey('created')) {
      context.handle(_createdMeta,
          created.isAcceptableOrUnknown(data['created']!, _createdMeta));
    }
    if (data.containsKey('updated')) {
      context.handle(_updatedMeta,
          updated.isAcceptableOrUnknown(data['updated']!, _updatedMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  BlobFile map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BlobFile(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      recordId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}recordId'])!,
      filename: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}filename'])!,
      data: attachedDatabase.typeMapping
          .read(DriftSqlType.blob, data['${effectivePrefix}data'])!,
      expiration: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}expiration']),
      created: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}created']),
      updated: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}updated']),
    );
  }

  @override
  $BlobFilesTable createAlias(String alias) {
    return $BlobFilesTable(attachedDatabase, alias);
  }
}

class BlobFile extends DataClass implements Insertable<BlobFile> {
  final int id;
  final String recordId;
  final String filename;
  final Uint8List data;
  final DateTime? expiration;
  final String? created;
  final String? updated;
  const BlobFile(
      {required this.id,
      required this.recordId,
      required this.filename,
      required this.data,
      this.expiration,
      this.created,
      this.updated});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['recordId'] = Variable<String>(recordId);
    map['filename'] = Variable<String>(filename);
    map['data'] = Variable<Uint8List>(data);
    if (!nullToAbsent || expiration != null) {
      map['expiration'] = Variable<DateTime>(expiration);
    }
    if (!nullToAbsent || created != null) {
      map['created'] = Variable<String>(created);
    }
    if (!nullToAbsent || updated != null) {
      map['updated'] = Variable<String>(updated);
    }
    return map;
  }

  BlobFilesCompanion toCompanion(bool nullToAbsent) {
    return BlobFilesCompanion(
      id: Value(id),
      recordId: Value(recordId),
      filename: Value(filename),
      data: Value(data),
      expiration: expiration == null && nullToAbsent
          ? const Value.absent()
          : Value(expiration),
      created: created == null && nullToAbsent
          ? const Value.absent()
          : Value(created),
      updated: updated == null && nullToAbsent
          ? const Value.absent()
          : Value(updated),
    );
  }

  factory BlobFile.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BlobFile(
      id: serializer.fromJson<int>(json['id']),
      recordId: serializer.fromJson<String>(json['recordId']),
      filename: serializer.fromJson<String>(json['filename']),
      data: serializer.fromJson<Uint8List>(json['data']),
      expiration: serializer.fromJson<DateTime?>(json['expiration']),
      created: serializer.fromJson<String?>(json['created']),
      updated: serializer.fromJson<String?>(json['updated']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'recordId': serializer.toJson<String>(recordId),
      'filename': serializer.toJson<String>(filename),
      'data': serializer.toJson<Uint8List>(data),
      'expiration': serializer.toJson<DateTime?>(expiration),
      'created': serializer.toJson<String?>(created),
      'updated': serializer.toJson<String?>(updated),
    };
  }

  BlobFile copyWith(
          {int? id,
          String? recordId,
          String? filename,
          Uint8List? data,
          Value<DateTime?> expiration = const Value.absent(),
          Value<String?> created = const Value.absent(),
          Value<String?> updated = const Value.absent()}) =>
      BlobFile(
        id: id ?? this.id,
        recordId: recordId ?? this.recordId,
        filename: filename ?? this.filename,
        data: data ?? this.data,
        expiration: expiration.present ? expiration.value : this.expiration,
        created: created.present ? created.value : this.created,
        updated: updated.present ? updated.value : this.updated,
      );
  BlobFile copyWithCompanion(BlobFilesCompanion data) {
    return BlobFile(
      id: data.id.present ? data.id.value : this.id,
      recordId: data.recordId.present ? data.recordId.value : this.recordId,
      filename: data.filename.present ? data.filename.value : this.filename,
      data: data.data.present ? data.data.value : this.data,
      expiration:
          data.expiration.present ? data.expiration.value : this.expiration,
      created: data.created.present ? data.created.value : this.created,
      updated: data.updated.present ? data.updated.value : this.updated,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BlobFile(')
          ..write('id: $id, ')
          ..write('recordId: $recordId, ')
          ..write('filename: $filename, ')
          ..write('data: $data, ')
          ..write('expiration: $expiration, ')
          ..write('created: $created, ')
          ..write('updated: $updated')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, recordId, filename,
      $driftBlobEquality.hash(data), expiration, created, updated);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BlobFile &&
          other.id == this.id &&
          other.recordId == this.recordId &&
          other.filename == this.filename &&
          $driftBlobEquality.equals(other.data, this.data) &&
          other.expiration == this.expiration &&
          other.created == this.created &&
          other.updated == this.updated);
}

class BlobFilesCompanion extends UpdateCompanion<BlobFile> {
  final Value<int> id;
  final Value<String> recordId;
  final Value<String> filename;
  final Value<Uint8List> data;
  final Value<DateTime?> expiration;
  final Value<String?> created;
  final Value<String?> updated;
  const BlobFilesCompanion({
    this.id = const Value.absent(),
    this.recordId = const Value.absent(),
    this.filename = const Value.absent(),
    this.data = const Value.absent(),
    this.expiration = const Value.absent(),
    this.created = const Value.absent(),
    this.updated = const Value.absent(),
  });
  BlobFilesCompanion.insert({
    this.id = const Value.absent(),
    required String recordId,
    required String filename,
    required Uint8List data,
    this.expiration = const Value.absent(),
    this.created = const Value.absent(),
    this.updated = const Value.absent(),
  })  : recordId = Value(recordId),
        filename = Value(filename),
        data = Value(data);
  static Insertable<BlobFile> custom({
    Expression<int>? id,
    Expression<String>? recordId,
    Expression<String>? filename,
    Expression<Uint8List>? data,
    Expression<DateTime>? expiration,
    Expression<String>? created,
    Expression<String>? updated,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (recordId != null) 'recordId': recordId,
      if (filename != null) 'filename': filename,
      if (data != null) 'data': data,
      if (expiration != null) 'expiration': expiration,
      if (created != null) 'created': created,
      if (updated != null) 'updated': updated,
    });
  }

  BlobFilesCompanion copyWith(
      {Value<int>? id,
      Value<String>? recordId,
      Value<String>? filename,
      Value<Uint8List>? data,
      Value<DateTime?>? expiration,
      Value<String?>? created,
      Value<String?>? updated}) {
    return BlobFilesCompanion(
      id: id ?? this.id,
      recordId: recordId ?? this.recordId,
      filename: filename ?? this.filename,
      data: data ?? this.data,
      expiration: expiration ?? this.expiration,
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
    if (recordId.present) {
      map['recordId'] = Variable<String>(recordId.value);
    }
    if (filename.present) {
      map['filename'] = Variable<String>(filename.value);
    }
    if (data.present) {
      map['data'] = Variable<Uint8List>(data.value);
    }
    if (expiration.present) {
      map['expiration'] = Variable<DateTime>(expiration.value);
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
    return (StringBuffer('BlobFilesCompanion(')
          ..write('id: $id, ')
          ..write('recordId: $recordId, ')
          ..write('filename: $filename, ')
          ..write('data: $data, ')
          ..write('expiration: $expiration, ')
          ..write('created: $created, ')
          ..write('updated: $updated')
          ..write(')'))
        .toString();
  }
}

abstract class _$DataBase extends GeneratedDatabase {
  _$DataBase(QueryExecutor e) : super(e);
  $DataBaseManager get managers => $DataBaseManager(this);
  late final $ServicesTable services = $ServicesTable(this);
  late final TextEntries textEntries = TextEntries(this);
  late final Trigger servicesInsert = Trigger(
      'CREATE TRIGGER services_insert AFTER INSERT ON services BEGIN INSERT INTO text_entries ("rowid", data) VALUES (new."rowid", new.data);END',
      'services_insert');
  late final Trigger servicesDelete = Trigger(
      'CREATE TRIGGER services_delete AFTER DELETE ON services BEGIN INSERT INTO text_entries (text_entries, "rowid", data) VALUES (\'delete\', old."rowid", old.data);END',
      'services_delete');
  late final Trigger servicesUpdate = Trigger(
      'CREATE TRIGGER services_update AFTER UPDATE ON services BEGIN INSERT INTO text_entries (text_entries, "rowid", data) VALUES (\'delete\', old."rowid", old.data);INSERT INTO text_entries ("rowid", data) VALUES (new."rowid", new.data);END',
      'services_update');
  late final $BlobFilesTable blobFiles = $BlobFilesTable(this);
  Selectable<SearchResult> _search(String query) {
    return customSelect(
        'SELECT"record"."id" AS "nested_0.id", "record"."data" AS "nested_0.data", "record"."service" AS "nested_0.service", "record"."created" AS "nested_0.created", "record"."updated" AS "nested_0.updated" FROM text_entries INNER JOIN services AS record ON record."rowid" = text_entries."rowid" WHERE text_entries MATCH ?1 ORDER BY rank',
        variables: [
          Variable<String>(query)
        ],
        readsFrom: {
          textEntries,
          services,
        }).asyncMap((QueryRow row) async => SearchResult(
          record: await services.mapFromRow(row, tablePrefix: 'nested_0'),
        ));
  }

  Selectable<SearchServiceResult> _searchService(String query, String service) {
    return customSelect(
        'SELECT"record"."id" AS "nested_0.id", "record"."data" AS "nested_0.data", "record"."service" AS "nested_0.service", "record"."created" AS "nested_0.created", "record"."updated" AS "nested_0.updated" FROM text_entries INNER JOIN services AS record ON record."rowid" = text_entries."rowid" WHERE text_entries MATCH ?1 AND record.service = ?2 ORDER BY rank',
        variables: [
          Variable<String>(query),
          Variable<String>(service)
        ],
        readsFrom: {
          textEntries,
          services,
        }).asyncMap((QueryRow row) async => SearchServiceResult(
          record: await services.mapFromRow(row, tablePrefix: 'nested_0'),
        ));
  }

  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
        services,
        textEntries,
        servicesInsert,
        servicesDelete,
        servicesUpdate,
        blobFiles
      ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules(
        [
          WritePropagation(
            on: TableUpdateQuery.onTableName('Services',
                limitUpdateKind: UpdateKind.insert),
            result: [
              TableUpdate('text_entries', kind: UpdateKind.insert),
            ],
          ),
          WritePropagation(
            on: TableUpdateQuery.onTableName('Services',
                limitUpdateKind: UpdateKind.delete),
            result: [
              TableUpdate('text_entries', kind: UpdateKind.insert),
            ],
          ),
          WritePropagation(
            on: TableUpdateQuery.onTableName('Services',
                limitUpdateKind: UpdateKind.update),
            result: [
              TableUpdate('text_entries', kind: UpdateKind.insert),
            ],
          ),
        ],
      );
}

typedef $$ServicesTableCreateCompanionBuilder = ServicesCompanion Function({
  Value<String> id,
  required Map<String, dynamic> data,
  required String service,
  Value<String?> created,
  Value<String?> updated,
  Value<int> rowid,
});
typedef $$ServicesTableUpdateCompanionBuilder = ServicesCompanion Function({
  Value<String> id,
  Value<Map<String, dynamic>> data,
  Value<String> service,
  Value<String?> created,
  Value<String?> updated,
  Value<int> rowid,
});

final class $$ServicesTableReferences
    extends BaseReferences<_$DataBase, $ServicesTable, Service> {
  $$ServicesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$BlobFilesTable, List<BlobFile>>
      _blobFilesRefsTable(_$DataBase db) =>
          MultiTypedResultKey.fromTable(db.blobFiles,
              aliasName:
                  $_aliasNameGenerator(db.services.id, db.blobFiles.recordId));

  $$BlobFilesTableProcessedTableManager get blobFilesRefs {
    final manager = $$BlobFilesTableTableManager($_db, $_db.blobFiles)
        .filter((f) => f.recordId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_blobFilesRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }
}

class $$ServicesTableFilterComposer
    extends Composer<_$DataBase, $ServicesTable> {
  $$ServicesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnWithTypeConverterFilters<Map<String, dynamic>, Map<String, dynamic>,
          String>
      get data => $composableBuilder(
          column: $table.data,
          builder: (column) => ColumnWithTypeConverterFilters(column));

  ColumnFilters<String> get service => $composableBuilder(
      column: $table.service, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get created => $composableBuilder(
      column: $table.created, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get updated => $composableBuilder(
      column: $table.updated, builder: (column) => ColumnFilters(column));

  Expression<bool> blobFilesRefs(
      Expression<bool> Function($$BlobFilesTableFilterComposer f) f) {
    final $$BlobFilesTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.blobFiles,
        getReferencedColumn: (t) => t.recordId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$BlobFilesTableFilterComposer(
              $db: $db,
              $table: $db.blobFiles,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$ServicesTableOrderingComposer
    extends Composer<_$DataBase, $ServicesTable> {
  $$ServicesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get data => $composableBuilder(
      column: $table.data, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get service => $composableBuilder(
      column: $table.service, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get created => $composableBuilder(
      column: $table.created, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get updated => $composableBuilder(
      column: $table.updated, builder: (column) => ColumnOrderings(column));
}

class $$ServicesTableAnnotationComposer
    extends Composer<_$DataBase, $ServicesTable> {
  $$ServicesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumnWithTypeConverter<Map<String, dynamic>, String> get data =>
      $composableBuilder(column: $table.data, builder: (column) => column);

  GeneratedColumn<String> get service =>
      $composableBuilder(column: $table.service, builder: (column) => column);

  GeneratedColumn<String> get created =>
      $composableBuilder(column: $table.created, builder: (column) => column);

  GeneratedColumn<String> get updated =>
      $composableBuilder(column: $table.updated, builder: (column) => column);

  Expression<T> blobFilesRefs<T extends Object>(
      Expression<T> Function($$BlobFilesTableAnnotationComposer a) f) {
    final $$BlobFilesTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.blobFiles,
        getReferencedColumn: (t) => t.recordId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$BlobFilesTableAnnotationComposer(
              $db: $db,
              $table: $db.blobFiles,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$ServicesTableTableManager extends RootTableManager<
    _$DataBase,
    $ServicesTable,
    Service,
    $$ServicesTableFilterComposer,
    $$ServicesTableOrderingComposer,
    $$ServicesTableAnnotationComposer,
    $$ServicesTableCreateCompanionBuilder,
    $$ServicesTableUpdateCompanionBuilder,
    (Service, $$ServicesTableReferences),
    Service,
    PrefetchHooks Function({bool blobFilesRefs})> {
  $$ServicesTableTableManager(_$DataBase db, $ServicesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ServicesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ServicesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ServicesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<Map<String, dynamic>> data = const Value.absent(),
            Value<String> service = const Value.absent(),
            Value<String?> created = const Value.absent(),
            Value<String?> updated = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ServicesCompanion(
            id: id,
            data: data,
            service: service,
            created: created,
            updated: updated,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            Value<String> id = const Value.absent(),
            required Map<String, dynamic> data,
            required String service,
            Value<String?> created = const Value.absent(),
            Value<String?> updated = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ServicesCompanion.insert(
            id: id,
            data: data,
            service: service,
            created: created,
            updated: updated,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) =>
                  (e.readTable(table), $$ServicesTableReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: ({blobFilesRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (blobFilesRefs) db.blobFiles],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (blobFilesRefs)
                    await $_getPrefetchedData<Service, $ServicesTable,
                            BlobFile>(
                        currentTable: table,
                        referencedTable:
                            $$ServicesTableReferences._blobFilesRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$ServicesTableReferences(db, table, p0)
                                .blobFilesRefs,
                        referencedItemsForCurrentItem: (item,
                                referencedItems) =>
                            referencedItems.where((e) => e.recordId == item.id),
                        typedResults: items)
                ];
              },
            );
          },
        ));
}

typedef $$ServicesTableProcessedTableManager = ProcessedTableManager<
    _$DataBase,
    $ServicesTable,
    Service,
    $$ServicesTableFilterComposer,
    $$ServicesTableOrderingComposer,
    $$ServicesTableAnnotationComposer,
    $$ServicesTableCreateCompanionBuilder,
    $$ServicesTableUpdateCompanionBuilder,
    (Service, $$ServicesTableReferences),
    Service,
    PrefetchHooks Function({bool blobFilesRefs})>;
typedef $TextEntriesCreateCompanionBuilder = TextEntriesCompanion Function({
  required String data,
  Value<int> rowid,
});
typedef $TextEntriesUpdateCompanionBuilder = TextEntriesCompanion Function({
  Value<String> data,
  Value<int> rowid,
});

class $TextEntriesFilterComposer extends Composer<_$DataBase, TextEntries> {
  $TextEntriesFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get data => $composableBuilder(
      column: $table.data, builder: (column) => ColumnFilters(column));
}

class $TextEntriesOrderingComposer extends Composer<_$DataBase, TextEntries> {
  $TextEntriesOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get data => $composableBuilder(
      column: $table.data, builder: (column) => ColumnOrderings(column));
}

class $TextEntriesAnnotationComposer extends Composer<_$DataBase, TextEntries> {
  $TextEntriesAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get data =>
      $composableBuilder(column: $table.data, builder: (column) => column);
}

class $TextEntriesTableManager extends RootTableManager<
    _$DataBase,
    TextEntries,
    TextEntry,
    $TextEntriesFilterComposer,
    $TextEntriesOrderingComposer,
    $TextEntriesAnnotationComposer,
    $TextEntriesCreateCompanionBuilder,
    $TextEntriesUpdateCompanionBuilder,
    (TextEntry, BaseReferences<_$DataBase, TextEntries, TextEntry>),
    TextEntry,
    PrefetchHooks Function()> {
  $TextEntriesTableManager(_$DataBase db, TextEntries table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $TextEntriesFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $TextEntriesOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $TextEntriesAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> data = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              TextEntriesCompanion(
            data: data,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String data,
            Value<int> rowid = const Value.absent(),
          }) =>
              TextEntriesCompanion.insert(
            data: data,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $TextEntriesProcessedTableManager = ProcessedTableManager<
    _$DataBase,
    TextEntries,
    TextEntry,
    $TextEntriesFilterComposer,
    $TextEntriesOrderingComposer,
    $TextEntriesAnnotationComposer,
    $TextEntriesCreateCompanionBuilder,
    $TextEntriesUpdateCompanionBuilder,
    (TextEntry, BaseReferences<_$DataBase, TextEntries, TextEntry>),
    TextEntry,
    PrefetchHooks Function()>;
typedef $$BlobFilesTableCreateCompanionBuilder = BlobFilesCompanion Function({
  Value<int> id,
  required String recordId,
  required String filename,
  required Uint8List data,
  Value<DateTime?> expiration,
  Value<String?> created,
  Value<String?> updated,
});
typedef $$BlobFilesTableUpdateCompanionBuilder = BlobFilesCompanion Function({
  Value<int> id,
  Value<String> recordId,
  Value<String> filename,
  Value<Uint8List> data,
  Value<DateTime?> expiration,
  Value<String?> created,
  Value<String?> updated,
});

final class $$BlobFilesTableReferences
    extends BaseReferences<_$DataBase, $BlobFilesTable, BlobFile> {
  $$BlobFilesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $ServicesTable _recordIdTable(_$DataBase db) => db.services
      .createAlias($_aliasNameGenerator(db.blobFiles.recordId, db.services.id));

  $$ServicesTableProcessedTableManager get recordId {
    final $_column = $_itemColumn<String>('recordId')!;

    final manager = $$ServicesTableTableManager($_db, $_db.services)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_recordIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }
}

class $$BlobFilesTableFilterComposer
    extends Composer<_$DataBase, $BlobFilesTable> {
  $$BlobFilesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get filename => $composableBuilder(
      column: $table.filename, builder: (column) => ColumnFilters(column));

  ColumnFilters<Uint8List> get data => $composableBuilder(
      column: $table.data, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get expiration => $composableBuilder(
      column: $table.expiration, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get created => $composableBuilder(
      column: $table.created, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get updated => $composableBuilder(
      column: $table.updated, builder: (column) => ColumnFilters(column));

  $$ServicesTableFilterComposer get recordId {
    final $$ServicesTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.recordId,
        referencedTable: $db.services,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ServicesTableFilterComposer(
              $db: $db,
              $table: $db.services,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$BlobFilesTableOrderingComposer
    extends Composer<_$DataBase, $BlobFilesTable> {
  $$BlobFilesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get filename => $composableBuilder(
      column: $table.filename, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<Uint8List> get data => $composableBuilder(
      column: $table.data, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get expiration => $composableBuilder(
      column: $table.expiration, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get created => $composableBuilder(
      column: $table.created, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get updated => $composableBuilder(
      column: $table.updated, builder: (column) => ColumnOrderings(column));

  $$ServicesTableOrderingComposer get recordId {
    final $$ServicesTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.recordId,
        referencedTable: $db.services,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ServicesTableOrderingComposer(
              $db: $db,
              $table: $db.services,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$BlobFilesTableAnnotationComposer
    extends Composer<_$DataBase, $BlobFilesTable> {
  $$BlobFilesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get filename =>
      $composableBuilder(column: $table.filename, builder: (column) => column);

  GeneratedColumn<Uint8List> get data =>
      $composableBuilder(column: $table.data, builder: (column) => column);

  GeneratedColumn<DateTime> get expiration => $composableBuilder(
      column: $table.expiration, builder: (column) => column);

  GeneratedColumn<String> get created =>
      $composableBuilder(column: $table.created, builder: (column) => column);

  GeneratedColumn<String> get updated =>
      $composableBuilder(column: $table.updated, builder: (column) => column);

  $$ServicesTableAnnotationComposer get recordId {
    final $$ServicesTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.recordId,
        referencedTable: $db.services,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ServicesTableAnnotationComposer(
              $db: $db,
              $table: $db.services,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$BlobFilesTableTableManager extends RootTableManager<
    _$DataBase,
    $BlobFilesTable,
    BlobFile,
    $$BlobFilesTableFilterComposer,
    $$BlobFilesTableOrderingComposer,
    $$BlobFilesTableAnnotationComposer,
    $$BlobFilesTableCreateCompanionBuilder,
    $$BlobFilesTableUpdateCompanionBuilder,
    (BlobFile, $$BlobFilesTableReferences),
    BlobFile,
    PrefetchHooks Function({bool recordId})> {
  $$BlobFilesTableTableManager(_$DataBase db, $BlobFilesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BlobFilesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BlobFilesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BlobFilesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> recordId = const Value.absent(),
            Value<String> filename = const Value.absent(),
            Value<Uint8List> data = const Value.absent(),
            Value<DateTime?> expiration = const Value.absent(),
            Value<String?> created = const Value.absent(),
            Value<String?> updated = const Value.absent(),
          }) =>
              BlobFilesCompanion(
            id: id,
            recordId: recordId,
            filename: filename,
            data: data,
            expiration: expiration,
            created: created,
            updated: updated,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String recordId,
            required String filename,
            required Uint8List data,
            Value<DateTime?> expiration = const Value.absent(),
            Value<String?> created = const Value.absent(),
            Value<String?> updated = const Value.absent(),
          }) =>
              BlobFilesCompanion.insert(
            id: id,
            recordId: recordId,
            filename: filename,
            data: data,
            expiration: expiration,
            created: created,
            updated: updated,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$BlobFilesTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: ({recordId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins: <
                  T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic>>(state) {
                if (recordId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.recordId,
                    referencedTable:
                        $$BlobFilesTableReferences._recordIdTable(db),
                    referencedColumn:
                        $$BlobFilesTableReferences._recordIdTable(db).id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ));
}

typedef $$BlobFilesTableProcessedTableManager = ProcessedTableManager<
    _$DataBase,
    $BlobFilesTable,
    BlobFile,
    $$BlobFilesTableFilterComposer,
    $$BlobFilesTableOrderingComposer,
    $$BlobFilesTableAnnotationComposer,
    $$BlobFilesTableCreateCompanionBuilder,
    $$BlobFilesTableUpdateCompanionBuilder,
    (BlobFile, $$BlobFilesTableReferences),
    BlobFile,
    PrefetchHooks Function({bool recordId})>;

class $DataBaseManager {
  final _$DataBase _db;
  $DataBaseManager(this._db);
  $$ServicesTableTableManager get services =>
      $$ServicesTableTableManager(_db, _db.services);
  $TextEntriesTableManager get textEntries =>
      $TextEntriesTableManager(_db, _db.textEntries);
  $$BlobFilesTableTableManager get blobFiles =>
      $$BlobFilesTableTableManager(_db, _db.blobFiles);
}

class SearchResult {
  final Service record;
  SearchResult({
    required this.record,
  });
}

class SearchServiceResult {
  final Service record;
  SearchServiceResult({
    required this.record,
  });
}
