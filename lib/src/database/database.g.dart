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
  static const VerificationMeta _cachedAtMeta =
      const VerificationMeta('cachedAt');
  @override
  late final GeneratedColumn<DateTime> cachedAt = GeneratedColumn<DateTime>(
      'cachedAt', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns =>
      [id, data, service, created, updated, cachedAt];
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
    if (data.containsKey('cachedAt')) {
      context.handle(_cachedAtMeta,
          cachedAt.isAcceptableOrUnknown(data['cachedAt']!, _cachedAtMeta));
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
      cachedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}cachedAt']),
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

  /// When the row was last written from the server or by a local change.
  /// Cache TTL maintenance expires rows by this time, not by the server's
  /// `updated` value (which can be old for data that is fetched daily).
  final DateTime? cachedAt;
  const Service(
      {required this.id,
      required this.data,
      required this.service,
      this.created,
      this.updated,
      this.cachedAt});
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
    if (!nullToAbsent || cachedAt != null) {
      map['cachedAt'] = Variable<DateTime>(cachedAt);
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
      cachedAt: cachedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(cachedAt),
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
      cachedAt: serializer.fromJson<DateTime?>(json['cachedAt']),
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
      'cachedAt': serializer.toJson<DateTime?>(cachedAt),
    };
  }

  Service copyWith(
          {String? id,
          Map<String, dynamic>? data,
          String? service,
          Value<String?> created = const Value.absent(),
          Value<String?> updated = const Value.absent(),
          Value<DateTime?> cachedAt = const Value.absent()}) =>
      Service(
        id: id ?? this.id,
        data: data ?? this.data,
        service: service ?? this.service,
        created: created.present ? created.value : this.created,
        updated: updated.present ? updated.value : this.updated,
        cachedAt: cachedAt.present ? cachedAt.value : this.cachedAt,
      );
  Service copyWithCompanion(ServicesCompanion data) {
    return Service(
      id: data.id.present ? data.id.value : this.id,
      data: data.data.present ? data.data.value : this.data,
      service: data.service.present ? data.service.value : this.service,
      created: data.created.present ? data.created.value : this.created,
      updated: data.updated.present ? data.updated.value : this.updated,
      cachedAt: data.cachedAt.present ? data.cachedAt.value : this.cachedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Service(')
          ..write('id: $id, ')
          ..write('data: $data, ')
          ..write('service: $service, ')
          ..write('created: $created, ')
          ..write('updated: $updated, ')
          ..write('cachedAt: $cachedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, data, service, created, updated, cachedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Service &&
          other.id == this.id &&
          other.data == this.data &&
          other.service == this.service &&
          other.created == this.created &&
          other.updated == this.updated &&
          other.cachedAt == this.cachedAt);
}

class ServicesCompanion extends UpdateCompanion<Service> {
  final Value<String> id;
  final Value<Map<String, dynamic>> data;
  final Value<String> service;
  final Value<String?> created;
  final Value<String?> updated;
  final Value<DateTime?> cachedAt;
  final Value<int> rowid;
  const ServicesCompanion({
    this.id = const Value.absent(),
    this.data = const Value.absent(),
    this.service = const Value.absent(),
    this.created = const Value.absent(),
    this.updated = const Value.absent(),
    this.cachedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ServicesCompanion.insert({
    this.id = const Value.absent(),
    required Map<String, dynamic> data,
    required String service,
    this.created = const Value.absent(),
    this.updated = const Value.absent(),
    this.cachedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : data = Value(data),
        service = Value(service);
  static Insertable<Service> custom({
    Expression<String>? id,
    Expression<String>? data,
    Expression<String>? service,
    Expression<String>? created,
    Expression<String>? updated,
    Expression<DateTime>? cachedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (data != null) 'data': data,
      if (service != null) 'service': service,
      if (created != null) 'created': created,
      if (updated != null) 'updated': updated,
      if (cachedAt != null) 'cachedAt': cachedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ServicesCompanion copyWith(
      {Value<String>? id,
      Value<Map<String, dynamic>>? data,
      Value<String>? service,
      Value<String?>? created,
      Value<String?>? updated,
      Value<DateTime?>? cachedAt,
      Value<int>? rowid}) {
    return ServicesCompanion(
      id: id ?? this.id,
      data: data ?? this.data,
      service: service ?? this.service,
      created: created ?? this.created,
      updated: updated ?? this.updated,
      cachedAt: cachedAt ?? this.cachedAt,
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
    if (cachedAt.present) {
      map['cachedAt'] = Variable<DateTime>(cachedAt.value);
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
          ..write('cachedAt: $cachedAt, ')
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

class $BlobFileStatsTable extends BlobFileStats
    with TableInfo<$BlobFileStatsTable, BlobFileStat> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BlobFileStatsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _fileIdMeta = const VerificationMeta('fileId');
  @override
  late final GeneratedColumn<int> fileId = GeneratedColumn<int>(
      'fileId', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _sizeMeta = const VerificationMeta('size');
  @override
  late final GeneratedColumn<int> size = GeneratedColumn<int>(
      'size', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _lastAccessMeta =
      const VerificationMeta('lastAccess');
  @override
  late final GeneratedColumn<DateTime> lastAccess = GeneratedColumn<DateTime>(
      'lastAccess', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [fileId, size, lastAccess];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'BlobFileStats';
  @override
  VerificationContext validateIntegrity(Insertable<BlobFileStat> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('fileId')) {
      context.handle(_fileIdMeta,
          fileId.isAcceptableOrUnknown(data['fileId']!, _fileIdMeta));
    }
    if (data.containsKey('size')) {
      context.handle(
          _sizeMeta, size.isAcceptableOrUnknown(data['size']!, _sizeMeta));
    } else if (isInserting) {
      context.missing(_sizeMeta);
    }
    if (data.containsKey('lastAccess')) {
      context.handle(
          _lastAccessMeta,
          lastAccess.isAcceptableOrUnknown(
              data['lastAccess']!, _lastAccessMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {fileId};
  @override
  BlobFileStat map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BlobFileStat(
      fileId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}fileId'])!,
      size: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}size'])!,
      lastAccess: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}lastAccess']),
    );
  }

  @override
  $BlobFileStatsTable createAlias(String alias) {
    return $BlobFileStatsTable(attachedDatabase, alias);
  }
}

class BlobFileStat extends DataClass implements Insertable<BlobFileStat> {
  /// `BlobFiles.id`.
  final int fileId;

  /// Byte length of the blob.
  final int size;

  /// Last write or cache hit; `null` (blobs cached before the upgrade to
  /// 0.7.0) counts as the oldest.
  final DateTime? lastAccess;
  const BlobFileStat(
      {required this.fileId, required this.size, this.lastAccess});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['fileId'] = Variable<int>(fileId);
    map['size'] = Variable<int>(size);
    if (!nullToAbsent || lastAccess != null) {
      map['lastAccess'] = Variable<DateTime>(lastAccess);
    }
    return map;
  }

  BlobFileStatsCompanion toCompanion(bool nullToAbsent) {
    return BlobFileStatsCompanion(
      fileId: Value(fileId),
      size: Value(size),
      lastAccess: lastAccess == null && nullToAbsent
          ? const Value.absent()
          : Value(lastAccess),
    );
  }

  factory BlobFileStat.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BlobFileStat(
      fileId: serializer.fromJson<int>(json['fileId']),
      size: serializer.fromJson<int>(json['size']),
      lastAccess: serializer.fromJson<DateTime?>(json['lastAccess']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'fileId': serializer.toJson<int>(fileId),
      'size': serializer.toJson<int>(size),
      'lastAccess': serializer.toJson<DateTime?>(lastAccess),
    };
  }

  BlobFileStat copyWith(
          {int? fileId,
          int? size,
          Value<DateTime?> lastAccess = const Value.absent()}) =>
      BlobFileStat(
        fileId: fileId ?? this.fileId,
        size: size ?? this.size,
        lastAccess: lastAccess.present ? lastAccess.value : this.lastAccess,
      );
  BlobFileStat copyWithCompanion(BlobFileStatsCompanion data) {
    return BlobFileStat(
      fileId: data.fileId.present ? data.fileId.value : this.fileId,
      size: data.size.present ? data.size.value : this.size,
      lastAccess:
          data.lastAccess.present ? data.lastAccess.value : this.lastAccess,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BlobFileStat(')
          ..write('fileId: $fileId, ')
          ..write('size: $size, ')
          ..write('lastAccess: $lastAccess')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(fileId, size, lastAccess);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BlobFileStat &&
          other.fileId == this.fileId &&
          other.size == this.size &&
          other.lastAccess == this.lastAccess);
}

class BlobFileStatsCompanion extends UpdateCompanion<BlobFileStat> {
  final Value<int> fileId;
  final Value<int> size;
  final Value<DateTime?> lastAccess;
  const BlobFileStatsCompanion({
    this.fileId = const Value.absent(),
    this.size = const Value.absent(),
    this.lastAccess = const Value.absent(),
  });
  BlobFileStatsCompanion.insert({
    this.fileId = const Value.absent(),
    required int size,
    this.lastAccess = const Value.absent(),
  }) : size = Value(size);
  static Insertable<BlobFileStat> custom({
    Expression<int>? fileId,
    Expression<int>? size,
    Expression<DateTime>? lastAccess,
  }) {
    return RawValuesInsertable({
      if (fileId != null) 'fileId': fileId,
      if (size != null) 'size': size,
      if (lastAccess != null) 'lastAccess': lastAccess,
    });
  }

  BlobFileStatsCompanion copyWith(
      {Value<int>? fileId, Value<int>? size, Value<DateTime?>? lastAccess}) {
    return BlobFileStatsCompanion(
      fileId: fileId ?? this.fileId,
      size: size ?? this.size,
      lastAccess: lastAccess ?? this.lastAccess,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (fileId.present) {
      map['fileId'] = Variable<int>(fileId.value);
    }
    if (size.present) {
      map['size'] = Variable<int>(size.value);
    }
    if (lastAccess.present) {
      map['lastAccess'] = Variable<DateTime>(lastAccess.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BlobFileStatsCompanion(')
          ..write('fileId: $fileId, ')
          ..write('size: $size, ')
          ..write('lastAccess: $lastAccess')
          ..write(')'))
        .toString();
  }
}

class $CachedResponsesTable extends CachedResponses
    with TableInfo<$CachedResponsesTable, CachedResponse> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedResponsesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _requestKeyMeta =
      const VerificationMeta('requestKey');
  @override
  late final GeneratedColumn<String> requestKey = GeneratedColumn<String>(
      'requestKey', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _responseDataMeta =
      const VerificationMeta('responseData');
  @override
  late final GeneratedColumn<String> responseData = GeneratedColumn<String>(
      'responseData', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _cachedAtMeta =
      const VerificationMeta('cachedAt');
  @override
  late final GeneratedColumn<DateTime> cachedAt = GeneratedColumn<DateTime>(
      'cachedAt', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      clientDefault: () => DateTime.now().toUtc());
  @override
  List<GeneratedColumn> get $columns => [requestKey, responseData, cachedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'CachedResponses';
  @override
  VerificationContext validateIntegrity(Insertable<CachedResponse> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('requestKey')) {
      context.handle(
          _requestKeyMeta,
          requestKey.isAcceptableOrUnknown(
              data['requestKey']!, _requestKeyMeta));
    } else if (isInserting) {
      context.missing(_requestKeyMeta);
    }
    if (data.containsKey('responseData')) {
      context.handle(
          _responseDataMeta,
          responseData.isAcceptableOrUnknown(
              data['responseData']!, _responseDataMeta));
    } else if (isInserting) {
      context.missing(_responseDataMeta);
    }
    if (data.containsKey('cachedAt')) {
      context.handle(_cachedAtMeta,
          cachedAt.isAcceptableOrUnknown(data['cachedAt']!, _cachedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {requestKey};
  @override
  CachedResponse map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedResponse(
      requestKey: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}requestKey'])!,
      responseData: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}responseData'])!,
      cachedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}cachedAt'])!,
    );
  }

  @override
  $CachedResponsesTable createAlias(String alias) {
    return $CachedResponsesTable(attachedDatabase, alias);
  }
}

class CachedResponse extends DataClass implements Insertable<CachedResponse> {
  /// A unique hash of the request details (method, path, query, body)
  /// that will serve as the primary key.
  final String requestKey;

  /// The raw JSON-encoded response data as a string.
  final String responseData;

  /// The timestamp of when this cache entry was created. Useful for
  /// future implementations of Time-To-Live (TTL) caching.
  final DateTime cachedAt;
  const CachedResponse(
      {required this.requestKey,
      required this.responseData,
      required this.cachedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['requestKey'] = Variable<String>(requestKey);
    map['responseData'] = Variable<String>(responseData);
    map['cachedAt'] = Variable<DateTime>(cachedAt);
    return map;
  }

  CachedResponsesCompanion toCompanion(bool nullToAbsent) {
    return CachedResponsesCompanion(
      requestKey: Value(requestKey),
      responseData: Value(responseData),
      cachedAt: Value(cachedAt),
    );
  }

  factory CachedResponse.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedResponse(
      requestKey: serializer.fromJson<String>(json['requestKey']),
      responseData: serializer.fromJson<String>(json['responseData']),
      cachedAt: serializer.fromJson<DateTime>(json['cachedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'requestKey': serializer.toJson<String>(requestKey),
      'responseData': serializer.toJson<String>(responseData),
      'cachedAt': serializer.toJson<DateTime>(cachedAt),
    };
  }

  CachedResponse copyWith(
          {String? requestKey, String? responseData, DateTime? cachedAt}) =>
      CachedResponse(
        requestKey: requestKey ?? this.requestKey,
        responseData: responseData ?? this.responseData,
        cachedAt: cachedAt ?? this.cachedAt,
      );
  CachedResponse copyWithCompanion(CachedResponsesCompanion data) {
    return CachedResponse(
      requestKey:
          data.requestKey.present ? data.requestKey.value : this.requestKey,
      responseData: data.responseData.present
          ? data.responseData.value
          : this.responseData,
      cachedAt: data.cachedAt.present ? data.cachedAt.value : this.cachedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedResponse(')
          ..write('requestKey: $requestKey, ')
          ..write('responseData: $responseData, ')
          ..write('cachedAt: $cachedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(requestKey, responseData, cachedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedResponse &&
          other.requestKey == this.requestKey &&
          other.responseData == this.responseData &&
          other.cachedAt == this.cachedAt);
}

class CachedResponsesCompanion extends UpdateCompanion<CachedResponse> {
  final Value<String> requestKey;
  final Value<String> responseData;
  final Value<DateTime> cachedAt;
  final Value<int> rowid;
  const CachedResponsesCompanion({
    this.requestKey = const Value.absent(),
    this.responseData = const Value.absent(),
    this.cachedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedResponsesCompanion.insert({
    required String requestKey,
    required String responseData,
    this.cachedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : requestKey = Value(requestKey),
        responseData = Value(responseData);
  static Insertable<CachedResponse> custom({
    Expression<String>? requestKey,
    Expression<String>? responseData,
    Expression<DateTime>? cachedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (requestKey != null) 'requestKey': requestKey,
      if (responseData != null) 'responseData': responseData,
      if (cachedAt != null) 'cachedAt': cachedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedResponsesCompanion copyWith(
      {Value<String>? requestKey,
      Value<String>? responseData,
      Value<DateTime>? cachedAt,
      Value<int>? rowid}) {
    return CachedResponsesCompanion(
      requestKey: requestKey ?? this.requestKey,
      responseData: responseData ?? this.responseData,
      cachedAt: cachedAt ?? this.cachedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (requestKey.present) {
      map['requestKey'] = Variable<String>(requestKey.value);
    }
    if (responseData.present) {
      map['responseData'] = Variable<String>(responseData.value);
    }
    if (cachedAt.present) {
      map['cachedAt'] = Variable<DateTime>(cachedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedResponsesCompanion(')
          ..write('requestKey: $requestKey, ')
          ..write('responseData: $responseData, ')
          ..write('cachedAt: $cachedAt, ')
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

abstract class _$DataBase extends GeneratedDatabase {
  _$DataBase(QueryExecutor e) : super(e);
  $DataBaseManager get managers => $DataBaseManager(this);
  late final $ServicesTable services = $ServicesTable(this);
  late final $BlobFilesTable blobFiles = $BlobFilesTable(this);
  late final $BlobFileStatsTable blobFileStats = $BlobFileStatsTable(this);
  late final Trigger blobFilesDelete = Trigger(
      'CREATE TRIGGER blob_files_delete AFTER DELETE ON BlobFiles BEGIN DELETE FROM BlobFileStats WHERE fileId = old.id;END',
      'blob_files_delete');
  late final $CachedResponsesTable cachedResponses =
      $CachedResponsesTable(this);
  late final Index idxServicesService = Index('idx_services_service',
      'CREATE INDEX idx_services_service ON Services (service)');
  late final Index idxBlobFilesRecord = Index('idx_blob_files_record',
      'CREATE INDEX idx_blob_files_record ON BlobFiles (recordId, filename)');
  late final Index idxBlobFileStatsAccess = Index('idx_blob_file_stats_access',
      'CREATE INDEX idx_blob_file_stats_access ON BlobFileStats (lastAccess, size)');
  late final TextEntries textEntries = TextEntries(this);
  late final Trigger servicesInsert = Trigger(
      'CREATE TRIGGER services_insert AFTER INSERT ON services BEGIN INSERT INTO text_entries ("rowid", data) VALUES (new."rowid", json_remove(new.data, \'\$.retryCount\', \'\$.pendingFields\', \'\$.pendingFiles\', \'\$.pendingOwner\', \'\$.pendingRev\', \'\$.syncError\', \'\$.pendingBase\', \'\$.baseUpdated\', \'\$.pendingDeltas\'));END',
      'services_insert');
  late final Trigger servicesDelete = Trigger(
      'CREATE TRIGGER services_delete AFTER DELETE ON services BEGIN INSERT INTO text_entries (text_entries, "rowid", data) VALUES (\'delete\', old."rowid", json_remove(old.data, \'\$.retryCount\', \'\$.pendingFields\', \'\$.pendingFiles\', \'\$.pendingOwner\', \'\$.pendingRev\', \'\$.syncError\', \'\$.pendingBase\', \'\$.baseUpdated\', \'\$.pendingDeltas\'));END',
      'services_delete');
  late final Trigger servicesUpdate = Trigger(
      'CREATE TRIGGER services_update AFTER UPDATE OF data ON services BEGIN INSERT INTO text_entries (text_entries, "rowid", data) VALUES (\'delete\', old."rowid", json_remove(old.data, \'\$.retryCount\', \'\$.pendingFields\', \'\$.pendingFiles\', \'\$.pendingOwner\', \'\$.pendingRev\', \'\$.syncError\', \'\$.pendingBase\', \'\$.baseUpdated\', \'\$.pendingDeltas\'));INSERT INTO text_entries ("rowid", data) VALUES (new."rowid", json_remove(new.data, \'\$.retryCount\', \'\$.pendingFields\', \'\$.pendingFiles\', \'\$.pendingOwner\', \'\$.pendingRev\', \'\$.syncError\', \'\$.pendingBase\', \'\$.baseUpdated\', \'\$.pendingDeltas\'));END',
      'services_update');
  Selectable<SearchResult> _search(String query, String? owner) {
    return customSelect(
        'SELECT"record"."id" AS "nested_0.id", "record"."data" AS "nested_0.data", "record"."service" AS "nested_0.service", "record"."created" AS "nested_0.created", "record"."updated" AS "nested_0.updated", "record"."cachedAt" AS "nested_0.cachedAt" FROM text_entries INNER JOIN services AS record ON record."rowid" = text_entries."rowid" WHERE text_entries MATCH ?1 AND(json_extract(record.data, \'\$.deleted\') IS NULL OR json_extract(record.data, \'\$.deleted\') = 0)AND(json_extract(record.data, \'\$.pendingOwner\') IS NULL OR json_extract(record.data, \'\$.pendingOwner\') = ?2)ORDER BY rank',
        variables: [
          Variable<String>(query),
          Variable<String>(owner)
        ],
        readsFrom: {
          this.textEntries,
          this.services,
        }).asyncMap((QueryRow row) async => SearchResult(
          record: await this.services.mapFromRow(row, tablePrefix: 'nested_0'),
        ));
  }

  Selectable<SearchServiceResult> _searchService(
      String query, String service, String? owner) {
    return customSelect(
        'SELECT"record"."id" AS "nested_0.id", "record"."data" AS "nested_0.data", "record"."service" AS "nested_0.service", "record"."created" AS "nested_0.created", "record"."updated" AS "nested_0.updated", "record"."cachedAt" AS "nested_0.cachedAt" FROM text_entries INNER JOIN services AS record ON record."rowid" = text_entries."rowid" WHERE text_entries MATCH ?1 AND record.service = ?2 AND(json_extract(record.data, \'\$.deleted\') IS NULL OR json_extract(record.data, \'\$.deleted\') = 0)AND(json_extract(record.data, \'\$.pendingOwner\') IS NULL OR json_extract(record.data, \'\$.pendingOwner\') = ?3)ORDER BY rank',
        variables: [
          Variable<String>(query),
          Variable<String>(service),
          Variable<String>(owner)
        ],
        readsFrom: {
          this.textEntries,
          this.services,
        }).asyncMap((QueryRow row) async => SearchServiceResult(
          record: await this.services.mapFromRow(row, tablePrefix: 'nested_0'),
        ));
  }

  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
        services,
        blobFiles,
        blobFileStats,
        blobFilesDelete,
        cachedResponses,
        idxServicesService,
        idxBlobFilesRecord,
        idxBlobFileStatsAccess,
        textEntries,
        servicesInsert,
        servicesDelete,
        servicesUpdate
      ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules(
        [
          WritePropagation(
            on: TableUpdateQuery.onTableName('BlobFiles',
                limitUpdateKind: UpdateKind.delete),
            result: [
              TableUpdate('BlobFileStats', kind: UpdateKind.delete),
            ],
          ),
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
  Value<DateTime?> cachedAt,
  Value<int> rowid,
});
typedef $$ServicesTableUpdateCompanionBuilder = ServicesCompanion Function({
  Value<String> id,
  Value<Map<String, dynamic>> data,
  Value<String> service,
  Value<String?> created,
  Value<String?> updated,
  Value<DateTime?> cachedAt,
  Value<int> rowid,
});

final class $$ServicesTableReferences
    extends BaseReferences<_$DataBase, $ServicesTable, Service> {
  $$ServicesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$BlobFilesTable, List<BlobFile>>
      _blobFilesRefsTable(_$DataBase db) =>
          MultiTypedResultKey.fromTable(db.blobFiles,
              aliasName: 'Services__id__BlobFiles__recordId');

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

  ColumnFilters<DateTime> get cachedAt => $composableBuilder(
      column: $table.cachedAt, builder: (column) => ColumnFilters(column));

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

  ColumnOrderings<DateTime> get cachedAt => $composableBuilder(
      column: $table.cachedAt, builder: (column) => ColumnOrderings(column));
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

  GeneratedColumn<DateTime> get cachedAt =>
      $composableBuilder(column: $table.cachedAt, builder: (column) => column);

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
            Value<DateTime?> cachedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ServicesCompanion(
            id: id,
            data: data,
            service: service,
            created: created,
            updated: updated,
            cachedAt: cachedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            Value<String> id = const Value.absent(),
            required Map<String, dynamic> data,
            required String service,
            Value<String?> created = const Value.absent(),
            Value<String?> updated = const Value.absent(),
            Value<DateTime?> cachedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ServicesCompanion.insert(
            id: id,
            data: data,
            service: service,
            created: created,
            updated: updated,
            cachedAt: cachedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$ServicesTable, Service>(table),
                    $$ServicesTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: ({blobFilesRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (blobFilesRefs) db.blobFiles],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (blobFilesRefs)
                    await $_getPrefetchedDataByColumns<Service, $ServicesTable,
                            BlobFile, $BlobFilesTable>(
                        currentTable: table,
                        referencedTable:
                            $$ServicesTableReferences._blobFilesRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$ServicesTableReferences(db, table, p0)
                                .blobFilesRefs,
                        currentColumn: 'id',
                        referencedColumn: 'recordId',
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

  static $ServicesTable _recordIdTable(_$DataBase db) =>
      db.services.createAlias('BlobFiles__recordId__Services__id');

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
                    e.readTable<$BlobFilesTable, BlobFile>(table),
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
typedef $$BlobFileStatsTableCreateCompanionBuilder = BlobFileStatsCompanion
    Function({
  Value<int> fileId,
  required int size,
  Value<DateTime?> lastAccess,
});
typedef $$BlobFileStatsTableUpdateCompanionBuilder = BlobFileStatsCompanion
    Function({
  Value<int> fileId,
  Value<int> size,
  Value<DateTime?> lastAccess,
});

class $$BlobFileStatsTableFilterComposer
    extends Composer<_$DataBase, $BlobFileStatsTable> {
  $$BlobFileStatsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get fileId => $composableBuilder(
      column: $table.fileId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get size => $composableBuilder(
      column: $table.size, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get lastAccess => $composableBuilder(
      column: $table.lastAccess, builder: (column) => ColumnFilters(column));
}

class $$BlobFileStatsTableOrderingComposer
    extends Composer<_$DataBase, $BlobFileStatsTable> {
  $$BlobFileStatsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get fileId => $composableBuilder(
      column: $table.fileId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get size => $composableBuilder(
      column: $table.size, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get lastAccess => $composableBuilder(
      column: $table.lastAccess, builder: (column) => ColumnOrderings(column));
}

class $$BlobFileStatsTableAnnotationComposer
    extends Composer<_$DataBase, $BlobFileStatsTable> {
  $$BlobFileStatsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get fileId =>
      $composableBuilder(column: $table.fileId, builder: (column) => column);

  GeneratedColumn<int> get size =>
      $composableBuilder(column: $table.size, builder: (column) => column);

  GeneratedColumn<DateTime> get lastAccess => $composableBuilder(
      column: $table.lastAccess, builder: (column) => column);
}

class $$BlobFileStatsTableTableManager extends RootTableManager<
    _$DataBase,
    $BlobFileStatsTable,
    BlobFileStat,
    $$BlobFileStatsTableFilterComposer,
    $$BlobFileStatsTableOrderingComposer,
    $$BlobFileStatsTableAnnotationComposer,
    $$BlobFileStatsTableCreateCompanionBuilder,
    $$BlobFileStatsTableUpdateCompanionBuilder,
    (
      BlobFileStat,
      BaseReferences<_$DataBase, $BlobFileStatsTable, BlobFileStat>
    ),
    BlobFileStat,
    PrefetchHooks Function()> {
  $$BlobFileStatsTableTableManager(_$DataBase db, $BlobFileStatsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BlobFileStatsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BlobFileStatsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BlobFileStatsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> fileId = const Value.absent(),
            Value<int> size = const Value.absent(),
            Value<DateTime?> lastAccess = const Value.absent(),
          }) =>
              BlobFileStatsCompanion(
            fileId: fileId,
            size: size,
            lastAccess: lastAccess,
          ),
          createCompanionCallback: ({
            Value<int> fileId = const Value.absent(),
            required int size,
            Value<DateTime?> lastAccess = const Value.absent(),
          }) =>
              BlobFileStatsCompanion.insert(
            fileId: fileId,
            size: size,
            lastAccess: lastAccess,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$BlobFileStatsTable, BlobFileStat>(table),
                    BaseReferences<_$DataBase, $BlobFileStatsTable,
                        BlobFileStat>(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$BlobFileStatsTableProcessedTableManager = ProcessedTableManager<
    _$DataBase,
    $BlobFileStatsTable,
    BlobFileStat,
    $$BlobFileStatsTableFilterComposer,
    $$BlobFileStatsTableOrderingComposer,
    $$BlobFileStatsTableAnnotationComposer,
    $$BlobFileStatsTableCreateCompanionBuilder,
    $$BlobFileStatsTableUpdateCompanionBuilder,
    (
      BlobFileStat,
      BaseReferences<_$DataBase, $BlobFileStatsTable, BlobFileStat>
    ),
    BlobFileStat,
    PrefetchHooks Function()>;
typedef $$CachedResponsesTableCreateCompanionBuilder = CachedResponsesCompanion
    Function({
  required String requestKey,
  required String responseData,
  Value<DateTime> cachedAt,
  Value<int> rowid,
});
typedef $$CachedResponsesTableUpdateCompanionBuilder = CachedResponsesCompanion
    Function({
  Value<String> requestKey,
  Value<String> responseData,
  Value<DateTime> cachedAt,
  Value<int> rowid,
});

class $$CachedResponsesTableFilterComposer
    extends Composer<_$DataBase, $CachedResponsesTable> {
  $$CachedResponsesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get requestKey => $composableBuilder(
      column: $table.requestKey, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get responseData => $composableBuilder(
      column: $table.responseData, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get cachedAt => $composableBuilder(
      column: $table.cachedAt, builder: (column) => ColumnFilters(column));
}

class $$CachedResponsesTableOrderingComposer
    extends Composer<_$DataBase, $CachedResponsesTable> {
  $$CachedResponsesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get requestKey => $composableBuilder(
      column: $table.requestKey, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get responseData => $composableBuilder(
      column: $table.responseData,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get cachedAt => $composableBuilder(
      column: $table.cachedAt, builder: (column) => ColumnOrderings(column));
}

class $$CachedResponsesTableAnnotationComposer
    extends Composer<_$DataBase, $CachedResponsesTable> {
  $$CachedResponsesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get requestKey => $composableBuilder(
      column: $table.requestKey, builder: (column) => column);

  GeneratedColumn<String> get responseData => $composableBuilder(
      column: $table.responseData, builder: (column) => column);

  GeneratedColumn<DateTime> get cachedAt =>
      $composableBuilder(column: $table.cachedAt, builder: (column) => column);
}

class $$CachedResponsesTableTableManager extends RootTableManager<
    _$DataBase,
    $CachedResponsesTable,
    CachedResponse,
    $$CachedResponsesTableFilterComposer,
    $$CachedResponsesTableOrderingComposer,
    $$CachedResponsesTableAnnotationComposer,
    $$CachedResponsesTableCreateCompanionBuilder,
    $$CachedResponsesTableUpdateCompanionBuilder,
    (
      CachedResponse,
      BaseReferences<_$DataBase, $CachedResponsesTable, CachedResponse>
    ),
    CachedResponse,
    PrefetchHooks Function()> {
  $$CachedResponsesTableTableManager(_$DataBase db, $CachedResponsesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedResponsesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedResponsesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedResponsesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> requestKey = const Value.absent(),
            Value<String> responseData = const Value.absent(),
            Value<DateTime> cachedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CachedResponsesCompanion(
            requestKey: requestKey,
            responseData: responseData,
            cachedAt: cachedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String requestKey,
            required String responseData,
            Value<DateTime> cachedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CachedResponsesCompanion.insert(
            requestKey: requestKey,
            responseData: responseData,
            cachedAt: cachedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$CachedResponsesTable, CachedResponse>(table),
                    BaseReferences<_$DataBase, $CachedResponsesTable,
                        CachedResponse>(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$CachedResponsesTableProcessedTableManager = ProcessedTableManager<
    _$DataBase,
    $CachedResponsesTable,
    CachedResponse,
    $$CachedResponsesTableFilterComposer,
    $$CachedResponsesTableOrderingComposer,
    $$CachedResponsesTableAnnotationComposer,
    $$CachedResponsesTableCreateCompanionBuilder,
    $$CachedResponsesTableUpdateCompanionBuilder,
    (
      CachedResponse,
      BaseReferences<_$DataBase, $CachedResponsesTable, CachedResponse>
    ),
    CachedResponse,
    PrefetchHooks Function()>;
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
              .map((e) => (
                    e.readTable<TextEntries, TextEntry>(table),
                    BaseReferences<_$DataBase, TextEntries, TextEntry>(
                        db, table, e)
                  ))
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

class $DataBaseManager {
  final _$DataBase _db;
  $DataBaseManager(this._db);
  $$ServicesTableTableManager get services =>
      $$ServicesTableTableManager(_db, _db.services);
  $$BlobFilesTableTableManager get blobFiles =>
      $$BlobFilesTableTableManager(_db, _db.blobFiles);
  $$BlobFileStatsTableTableManager get blobFileStats =>
      $$BlobFileStatsTableTableManager(_db, _db.blobFileStats);
  $$CachedResponsesTableTableManager get cachedResponses =>
      $$CachedResponsesTableTableManager(_db, _db.cachedResponses);
  $TextEntriesTableManager get textEntries =>
      $TextEntriesTableManager(_db, _db.textEntries);
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
