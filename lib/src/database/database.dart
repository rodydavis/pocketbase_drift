import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:drift/drift.dart';
import 'package:logging/logging.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:pocketbase_drift/src/database/filter_parser.dart';

import 'tables.dart';
import '../pocketbase/services/sync_support.dart';

part 'database.g.dart';

/// Keys the package stores inside cached record JSON to track local state.
///
/// They are visible in `RecordModel.data` of cached records and are never
/// sent to the server.
abstract final class RecordMeta {
  /// `true` once the server holds this version, `false` while a local change
  /// is pending. Rows written by older versions may lack the key (= synced).
  static const synced = 'synced';

  /// The record was created locally and does not exist on the server yet.
  static const isNew = 'isNew';

  /// Tombstone: deleted locally, the deletion is not on the server yet.
  static const deleted = 'deleted';

  /// Local-only row (written with [RequestPolicy.cacheOnly]); never synced.
  static const noSync = 'noSync';

  /// Failed sync attempts that the server rejected.
  static const retryCount = 'retryCount';

  /// Names of the fields changed by pending local updates. Sync sends only
  /// these fields, so other devices' changes to other fields survive.
  static const pendingFields = 'pendingFields';

  /// Files attached by pending local writes: `[{field, name}]`, where
  /// `field` is the multipart key used (`images`, `images+`, ...) and `name`
  /// the local blob name.
  static const pendingFiles = 'pendingFiles';

  /// Auth record id of the account that made the pending change. Changes
  /// from another account are hidden and not synced until it logs in again.
  static const pendingOwner = 'pendingOwner';

  /// Increments with every local change, so a sync can tell whether the row
  /// changed while its request was in flight.
  static const pendingRev = 'pendingRev';

  /// Set when the server rejected the change permanently; the row stays
  /// pending (visible in `pendingRecords()`) but automatic sync skips it.
  static const syncError = 'syncError';

  static const keys = {
    synced,
    isNew,
    deleted,
    noSync,
    retryCount,
    pendingFields,
    pendingFiles,
    pendingOwner,
    pendingRev,
    syncError,
  };

  /// Record keys the server owns or that only exist in responses.
  static const systemKeys = {
    'id',
    'created',
    'updated',
    'collectionId',
    'collectionName',
    'expand',
  };

  /// JSON booleans read through a `fields` projection come back as 0/1.
  static bool flag(Object? value) => value == true || value == 1;

  /// Whether [data] holds an unsynced local change (including tombstones).
  static bool isPending(Map<String, dynamic> data) {
    final s = data[synced];
    return (s == false || s == 0) && !flag(data[noSync]);
  }

  /// A copy of [data] without the package's bookkeeping keys.
  static Map<String, dynamic> strip(Map<String, dynamic> data) =>
      Map<String, dynamic>.of(data)..removeWhere((k, _) => keys.contains(k));
}

/// SQL predicate for pending rows (see [RecordMeta.isPending]).
const _pendingSql =
    "(COALESCE(json_extract(data, '\$.synced'), 1) = 0 AND COALESCE(json_extract(data, '\$.noSync'), 0) = 0)";

/// SQL predicate hiding pending rows queued by another account; the single
/// variable is the active owner (may be NULL).
const _ownerVisibleSql =
    "(json_extract(data, '\$.pendingOwner') IS NULL OR json_extract(data, '\$.pendingOwner') = ?)";

const _notDeletedSql =
    "(json_extract(data, '\$.deleted') IS NULL OR json_extract(data, '\$.deleted') = 0)";

/// PocketBase timestamp format with millisecond precision:
/// `2026-11-04 10:00:00.123Z`.
String pbTimestamp([DateTime? time]) {
  final t = (time ?? DateTime.now()).toUtc();
  return DateTime.fromMillisecondsSinceEpoch(t.millisecondsSinceEpoch,
          isUtc: true)
      .toIso8601String()
      .replaceFirst('T', ' ');
}

@DriftDatabase(
  tables: [Services, BlobFiles, CachedResponses],
  include: {'sql/search.drift'},
)
class DataBase extends _$DataBase {
  DataBase(super.e) : logger = Logger('PocketBaseDrift.db');

  final Logger logger;

  /// Returns the auth record id of the logged-in account; `$PocketBase`
  /// points it at its auth store.
  ///
  /// Pending rows carry the id of the account that wrote them; reads hide
  /// pending rows of other accounts so data kept across a logout never shows
  /// up for the next user.
  String? Function() ownerResolver = _noOwner;

  static String? _noOwner() => null;

  /// The logged-in account's id, read at query time.
  String? get activeOwner => ownerResolver();

  static String _getUpdatedTimestamp(Map<String, dynamic> data) {
    final updated = data['updated'];
    if (updated is String && updated.isNotEmpty) return updated;
    return pbTimestamp();
  }

  static String _getCreatedTimestamp(Map<String, dynamic> data) {
    final created = data['created'];
    if (created is String && created.isNotEmpty) return created;
    return pbTimestamp();
  }

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        await m.createAll();
      },
      onUpgrade: (Migrator m, int from, int to) async {
        if (from < 2) {
          await m.createTable(blobFiles);
        }
        if (from < 3) {
          await m.createTable(cachedResponses);
        }
        if (from < 4) {
          // Re-index FTS only when the record JSON changes.
          await m.drop(servicesUpdate);
          await m.createTrigger(servicesUpdate);
          await m.addColumn(services, services.cachedAt);
          // Existing rows start their TTL at the upgrade.
          await update(services)
              .write(ServicesCompanion(cachedAt: Value(DateTime.now())));
          await m.createIndex(idxServicesService);
          await m.createIndex(idxBlobFilesRecord);
        }
      },
    );
  }

  static final _inTransaction = Object();

  /// Marks the zone of [action], so code inside a transaction can tell.
  @override
  Future<T> transaction<T>(
    Future<T> Function() action, {
    bool requireNew = false,
  }) =>
      super.transaction(
        () => runZoned(action, zoneValues: {_inTransaction: true}),
        requireNew: requireNew,
      );

  // -- Schema cache --------------------------------------------------------

  Future<void> _schemaWrite = Future.value();
  ({
    Map<String, CollectionModel> byName,
    Map<String, CollectionModel> byId
  })? _schema;
  int _schemaGeneration = 0;

  void _invalidateSchema(String service) {
    if (service != 'schema') return;
    _schema = null;
    _schemaGeneration++;
  }

  Future<
      ({
        Map<String, CollectionModel> byName,
        Map<String, CollectionModel> byId
      })> _loadSchema() async {
    // Inside a transaction a queued setSchema cannot run before this
    // transaction ends (it needs the same lock), so waiting for it would
    // deadlock; the transaction reads the schema as it is now.
    if (Zone.current[_inTransaction] != true) await _schemaWrite;
    while (true) {
      final cached = _schema;
      if (cached != null) return cached;
      final generation = _schemaGeneration;
      final rows = await (select(services)
            ..where((t) => t.service.equals('schema')))
          .get();
      final list = rows
          .map((r) => CollectionModel.fromJson({...r.data, 'id': r.id}))
          .toList();
      if (generation != _schemaGeneration) continue;
      return _schema = (
        byName: {for (final c in list) c.name: c},
        byId: {for (final c in list) c.id: c},
      );
    }
  }

  /// Cached collection definition by name (waits for a pending [setSchema]).
  Future<CollectionModel?> collectionByName(String name) async =>
      (await _loadSchema()).byName[name];

  /// Cached collection definition by id (waits for a pending [setSchema]).
  Future<CollectionModel?> collectionById(String id) async =>
      (await _loadSchema()).byId[id];

  /// All cached collection definitions (waits for a pending [setSchema]).
  Future<List<CollectionModel>> allCollections() async =>
      (await _loadSchema()).byName.values.toList();

  // -- Queries -------------------------------------------------------------

  Selectable<Service> search(String query, {String? service}) {
    if (service != null) {
      return _searchService(query, service, activeOwner).map((p0) => p0.record);
    } else {
      return _search(query, activeOwner).map((p0) => p0.record);
    }
  }

  (String, List<Variable>) queryBuilder(
    String service, {
    String? fields,
    String? filter,
    String? sort,
    int? offset,
    int? limit,
    bool includeDeleted = false,
    bool includeOtherOwners = false,
  }) {
    final baseFields = <String>{
      "id",
      "created",
      "updated",
    };

    String fixField(
      String field, {
      bool alias = true,
    }) {
      field = field.trim();
      if (field.toLowerCase().contains('count(')) {
        return field;
      }
      if (baseFields.contains(field)) return field;
      var str = "json_extract(services.data, '\$.$field')";
      if (alias) str += ' as $field';
      return str;
    }

    final sb = StringBuffer();
    final variables = <Variable>[];

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
    sb.write(' FROM services');
    sb.write(" WHERE service = ?");
    variables.add(Variable.withString(service));

    if (!includeDeleted) {
      // Tombstones (records deleted offline that still await server sync)
      // must never surface in regular reads.
      sb.write(
          " AND (json_extract(services.data, '\$.deleted') IS NULL OR json_extract(services.data, '\$.deleted') = 0)");
    }

    if (!includeOtherOwners) {
      sb.write(" AND $_ownerVisibleSql");
      variables.add(Variable<String>(activeOwner));
    }

    if (filter != null && filter.isNotEmpty) {
      final parser =
          FilterParser(filter, baseFields: baseFields, authId: activeOwner);
      final whereClause = parser.parse();
      sb.write(' AND ($whereClause)');
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
            sb.write(fixField(part.substring(1).trim(), alias: false));
            sb.write(' DESC');
          } else if (part.startsWith('+')) {
            sb.write(fixField(part.substring(1).trim(), alias: false));
            sb.write(' ASC');
          } else {
            sb.write(fixField(part.trim(), alias: false));
            sb.write(' ASC');
          }
          if (i < parts.length - 1) {
            sb.write(', ');
          }
        }
      }
    }
    if (limit != null) {
      sb.write(' LIMIT ?');
      variables.add(Variable.withInt(limit));
    } else if (offset != null) {
      // SQLite needs a LIMIT before OFFSET.
      sb.write(' LIMIT -1');
    }
    if (offset != null) {
      sb.write(' OFFSET ?');
      variables.add(Variable.withInt(offset));
    }
    return (sb.toString(), variables);
  }

  Selectable<CollectionModel> $collections({
    String? service,
  }) {
    if (service != null) {
      final query = customSelect(
        "SELECT * FROM services WHERE service = 'schema' AND json_extract(services.data, '\$.name') = ?",
        variables: [Variable.withString(service)],
        readsFrom: {services},
      ).map(parseRow);
      return query.map(CollectionModel.fromJson);
    } else {
      final query = customSelect(
        "SELECT * FROM services WHERE service = 'schema'",
        readsFrom: {services},
      ).map(parseRow);
      return query.map(CollectionModel.fromJson);
    }
  }

  /// Queries records for a service.
  ///
  /// By default records that were deleted offline and still await server
  /// sync (tombstones, `deleted: true`) are excluded. Internal callers that
  /// operate on the pending-sync queue pass [includeDeleted]: true.
  ///
  /// [expand] is resolved from the cache for the whole result at once: one
  /// query per relation field and nesting level, not per row.
  Selectable<Map<String, dynamic>> $query(
    String service, {
    String? expand,
    String? fields,
    String? filter,
    String? sort,
    int? offset,
    int? limit,
    bool includeDeleted = false,
    bool includeOtherOwners = false,
  }) {
    final (query, variables) = queryBuilder(
      service,
      fields: fields,
      filter: filter,
      sort: sort,
      offset: offset,
      limit: limit,
      includeDeleted: includeDeleted,
      includeOtherOwners: includeOtherOwners,
    );
    logger.finer('query: $query, variables: $variables');
    final rows = customSelect(
      query,
      variables: variables,
      readsFrom: {services},
    ).map(parseRow);
    if (expand == null || expand.trim().isEmpty) return rows;
    return _ExpandedSelectable(
      rows,
      (records) => _expandRecords(service, records, expand, 0),
    );
  }

  static Iterable<String> _relationIds(Object? raw) sync* {
    if (raw is String && raw.isNotEmpty) {
      yield raw;
    } else if (raw is List) {
      yield* raw.whereType<String>().where((id) => id.isNotEmpty);
    }
  }

  Future<List<Map<String, dynamic>>> _expandRecords(
    String service,
    List<Map<String, dynamic>> records,
    String expand,
    int depth,
  ) async {
    if (records.isEmpty) return records;
    if (depth >= 6) throw Exception('Max 6 levels expand supported');

    // relation field -> nested expand paths
    final targets = <String, List<String>>{};
    for (final raw in expand.split(',')) {
      final target = raw.trim();
      if (target.isEmpty) continue;
      final dot = target.indexOf('.');
      final field = dot == -1 ? target : target.substring(0, dot);
      if (field.contains('(')) {
        throw UnimplementedError('Indirect expand not supported yet');
      }
      final nested = targets.putIfAbsent(field, () => []);
      if (dot != -1) nested.add(target.substring(dot + 1));
    }

    final schema = await _loadSchema();
    final collection = schema.byName[service];
    if (collection == null) {
      logger.fine('expand: no local schema for "$service"');
      return records;
    }

    for (final record in records) {
      record['expand'] = <String, dynamic>{};
    }

    for (final entry in targets.entries) {
      final field =
          collection.fields.where((f) => f.name == entry.key).firstOrNull;
      if (field == null || field.type != 'relation') continue;
      final target = schema.byId[field.data['collectionId']];
      if (target == null) continue;
      final maxSelect = field.data['maxSelect'];
      final isSingle =
          maxSelect == null || (maxSelect is num && maxSelect <= 1);

      final ids = <String>{
        for (final record in records) ..._relationIds(record[entry.key]),
      };
      final related = await _fetchByIds(
        target.name,
        ids,
        nestedExpand: entry.value.join(','),
        depth: depth + 1,
      );

      for (final record in records) {
        final found = [
          for (final id in _relationIds(record[entry.key]))
            if (related[id] != null) related[id]!,
        ];
        (record['expand'] as Map<String, dynamic>)[entry.key] =
            isSingle ? (found.isEmpty ? null : found.first) : found;
      }
    }
    return records;
  }

  Future<Map<String, Map<String, dynamic>>> _fetchByIds(
    String service,
    Set<String> ids, {
    String nestedExpand = '',
    int depth = 0,
  }) async {
    final out = <String, Map<String, dynamic>>{};
    if (ids.isEmpty) return out;
    final list = ids.toList();
    const chunkSize = 500;
    for (var i = 0; i < list.length; i += chunkSize) {
      final chunk = list.sublist(i, math.min(i + chunkSize, list.length));
      final placeholders = List.filled(chunk.length, '?').join(', ');
      final rows = await customSelect(
        'SELECT * FROM services WHERE service = ? AND id IN ($placeholders) '
        'AND $_notDeletedSql AND $_ownerVisibleSql',
        variables: [
          Variable.withString(service),
          for (final id in chunk) Variable.withString(id),
          Variable<String>(activeOwner),
        ],
        readsFrom: {services},
      ).get();
      for (final row in rows) {
        final record = parseRow(row);
        out[record['id'] as String] = record;
      }
    }
    if (nestedExpand.isNotEmpty) {
      await _expandRecords(service, out.values.toList(), nestedExpand, depth);
    }
    return out;
  }

  /// Number of (non-deleted, visible) records in [service] matching
  /// [filter].
  Future<int> $count(String service, {String? filter}) async {
    final (query, variables) = queryBuilder(
      service,
      fields: 'COUNT(*)',
      filter: filter,
    );
    final result = await customSelect(
      query,
      variables: variables,
      readsFrom: {services},
    ).getSingleOrNull();
    return result?.read<int>('COUNT(*)') ?? 0;
  }

  Map<String, dynamic> parseRow(QueryRow row) {
    const fields = [
      'id',
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
        result[field] = row.readNullable<String>(field);
        continue;
      }
    }

    return result;
  }

  /// The parsed row for [id], or null.
  Future<Map<String, dynamic>?> rowById(String service, String id) async {
    final row = await (select(services)
          ..where((r) => r.service.equals(service) & r.id.equals(id)))
        .getSingleOrNull();
    if (row == null) return null;
    return {
      ...row.data,
      'id': row.id,
      'created': row.created,
      'updated': row.updated,
    };
  }

  Future<Map<String, Map<String, dynamic>>> _rowsByIds(
    String service,
    Iterable<String> ids,
  ) async {
    final out = <String, Map<String, dynamic>>{};
    final list = ids.toSet().toList();
    const chunkSize = 500;
    for (var i = 0; i < list.length; i += chunkSize) {
      final chunk = list.sublist(i, math.min(i + chunkSize, list.length));
      final rows = await (select(services)
            ..where((r) => r.service.equals(service) & r.id.isIn(chunk)))
          .get();
      for (final row in rows) {
        out[row.id] = {
          ...row.data,
          'id': row.id,
          'created': row.created,
          'updated': row.updated,
        };
      }
    }
    return out;
  }

  /// Validates data against collection schema
  ///
  /// Throws exception if data is invalid for each field
  ///
  /// Returns true if data is valid
  bool validateData(CollectionModel collection, Map<String, dynamic> data) {
    for (final field in collection.fields) {
      // System fields are handled by Drift/PocketBase, not user input.
      if (field.system) continue;

      final value = data[field.name];

      // Check for required fields
      if (field.required &&
          (value == null || (value is String && value.isEmpty))) {
        throw Exception('Field ${field.name} is required');
      }

      // If the field is not required and has no value, skip further checks.
      if (value == null) continue;

      // Type-specific validation
      switch (field.type) {
        case 'number':
          if (value is! num) {
            throw Exception(
                'Field ${field.name} must be a number, but got ${value.runtimeType}');
          }
          break;
        case 'bool':
          if (value is! bool) {
            throw Exception(
                'Field ${field.name} must be a boolean, but got ${value.runtimeType}');
          }
          break;
        case 'date':
          // Allow empty string for non-required date fields
          if (value is String && value.isEmpty && !field.required) {
            break;
          }
          if (value is! String || DateTime.tryParse(value) == null) {
            throw Exception(
                'Field ${field.name} must be a valid ISO 8601 date string, but got "$value"');
          }
          break;
        case 'text':
        case 'editor':
          if (value is! String) {
            throw Exception(
                'Field ${field.name} must be a string, but got ${value.runtimeType}');
          }
          break;
        case 'url':
          // Allow empty string for non-required date fields
          if (value is String && value.isEmpty && !field.required) {
            break;
          }
          final uri = Uri.tryParse(value);
          if (value is! String || uri == null || !uri.isAbsolute) {
            throw Exception(
                'Field ${field.name} must be a valid URL string, but got "$value"');
          }
          break;
        case 'email':
          // Allow empty string for non-required email fields
          if (value is String && value.isEmpty && !field.required) {
            break;
          }
          if (value is! String) {
            throw Exception(
                'Field ${field.name} must be a valid email string, but got ${value.runtimeType}');
          }
          const pattern =
              r'^(([^<>()[\]\\.,;:\s@\"]+(\.[^<>()[\]\\.,;:\s@\"]+)*)|(\".+\"))@((\[[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\])|(([a-zA-Z\-0-9]+\.)+[a-zA-Z]{2,}))$';
          if (!RegExp(pattern).hasMatch(value)) {
            throw Exception('Field ${field.name} must be a valid email');
          }
          break;
        case 'select':
        case 'file':
        case 'relation':
          // Per PocketBase docs:
          // - maxSelect <= 1 (including 0, 1, or null) = single-select (String)
          // - maxSelect >= 2 = multi-select (List)
          final maxSelect = field.data['maxSelect'];
          final isSingleSelect = maxSelect == null || maxSelect <= 1;
          if (isSingleSelect) {
            if (value is! String) {
              throw Exception(
                  'Field ${field.name} (single-select) must be a string, but got ${value.runtimeType}');
            }
          } else {
            if (value is! List) {
              throw Exception(
                  'Field ${field.name} (multi-select) must be a list, but got ${value.runtimeType}');
            }
          }
          break;
        // 'json' type is not validated for structure.
      }
    }
    return true;
  }

  ServicesCompanion _row(String service, String id, Map<String, dynamic> data) {
    return ServicesCompanion.insert(
      id: Value(id),
      service: service,
      data: data,
      created: Value(_getCreatedTimestamp(data)),
      updated: Value(_getUpdatedTimestamp(data)),
      cachedAt: Value(DateTime.now()),
    );
  }

  /// Inserts or replaces a row. `expand` data is not stored with the row:
  /// the expanded records are cached in their own collections and the
  /// expansion is recomputed when querying with `expand`.
  Future<Map<String, dynamic>> $create(
    String service,
    Map<String, dynamic> data, {
    bool validate = true,
  }) async {
    final input = Map<String, dynamic>.of(data);
    if (input['id'] == '') input.remove('id');
    final id = input['id'] as String?;

    final mutableData = Map<String, dynamic>.from(input)..remove('id');

    if (validate && service != 'schema') {
      final collection = await collectionByName(service);
      if (collection == null) {
        throw Exception(
          'Failed to validate data for service "$service": Collection schema not found in local database. Ensure schemas are loaded (await client.setSchema(...)) before creating/updating records.',
        );
      }
      validateData(collection, mutableData);
    }

    final stored = Map<String, dynamic>.of(input)..remove('expand');
    final item = ServicesCompanion.insert(
      id: id != null ? Value(id) : const Value.absent(),
      service: service,
      data: stored,
      created: Value(_getCreatedTimestamp(input)),
      updated: Value(_getUpdatedTimestamp(input)),
      cachedAt: Value(DateTime.now()),
    );

    final insertedService = await into(services).insertReturning(
      item,
      onConflict: DoUpdate((old) => item),
    );
    _invalidateSchema(service);

    await _cacheExpandedRecords(service, input);

    return <String, dynamic>{
      ...insertedService.data,
      'id': insertedService.id,
      'created': insertedService.created,
      'updated': insertedService.updated,
    };
  }

  /// Caches records embedded in `expand` into their own collections, so they
  /// are available for local expansion and direct queries.
  Future<void> _cacheExpandedRecords(
    String parentService,
    Map<String, dynamic> data,
  ) async {
    final expand = data['expand'];
    if (expand is! Map<String, dynamic> || expand.isEmpty) return;

    final schema = await _loadSchema();
    final collection = schema.byName[parentService];
    if (collection == null) return;

    for (final entry in expand.entries) {
      final field =
          collection.fields.where((f) => f.name == entry.key).firstOrNull;
      if (field == null || field.type != 'relation') continue;
      final target = schema.byId[field.data['collectionId']];
      if (target == null) continue;

      final value = entry.value;
      final related = <Map<String, dynamic>>[
        if (value is Map<String, dynamic>) value,
        if (value is List) ...value.whereType<Map<String, dynamic>>(),
      ];
      if (related.isEmpty) continue;
      try {
        await upsertServerRecords(target.name, related, onlyIfNewer: true);
      } catch (e) {
        logger.fine('Error caching expanded records of "$parentService": $e');
      }
    }
  }

  Future<Map<String, dynamic>> $update(
    String service,
    String id,
    Map<String, dynamic> data, {
    bool validate = true,
  }) async {
    // Validate that ID is not empty - calling update with an empty ID
    // would silently create a new record, which is almost never intended.
    if (id.isEmpty) {
      throw ArgumentError.value(
        id,
        'id',
        'Cannot update a record with an empty ID in service "$service". '
            'This would create a new record instead of updating. '
            'If you intended to create a new record, use \$create() instead.',
      );
    }
    final existing = await rowById(service, id);
    final merged = <String, dynamic>{
      ...?existing,
      ...data,
      'id': id,
    };
    // A local mutation without an explicit timestamp gets a new one.
    if (!data.containsKey('updated') ||
        data['updated'] == null ||
        data['updated'] == '') {
      merged['updated'] = pbTimestamp();
    }
    return $create(service, merged, validate: validate);
  }

  Future<void> $delete(
    String service,
    String id, {
    Batch? batch,
  }) async {
    if (batch != null) {
      batch.deleteWhere(
        services,
        (r) => r.service.equals(service) & r.id.equals(id),
      );
      return;
    }

    await transaction(() async {
      // Every blob of the record (all fields, thumbnails, pending uploads).
      await (delete(blobFiles)..where((t) => t.recordId.equals(id))).go();
      await (delete(services)
            ..where((r) => r.service.equals(service))
            ..where((r) => r.id.equals(id)))
          .go();
    });
    _invalidateSchema(service);
  }

  Future<void> deleteAll(
    String service, {
    List<String>? ids,
  }) async {
    if (ids != null) {
      await batch((b) async {
        for (final id in ids) {
          await $delete(service, id, batch: b);
        }
      });
    } else {
      final query = delete(services)..where((r) => r.service.equals(service));
      await query.go();
    }
    _invalidateSchema(service);
  }

  Future<void> setLocal(
    String service,
    List<Map<String, dynamic>> items, {
    bool removeAll = true,
  }) async {
    await transaction(() async {
      if (removeAll) {
        await (delete(services)..where((r) => r.service.equals(service))).go();
      }
      await batch((b) {
        for (final item in items) {
          final id = item['id'] as String?;
          if (id == null || id.isEmpty) {
            logger.warning(
                'Skipping record in setLocal for service "$service" due to missing ID: $item');
            continue;
          }
          final row = _row(service, id, item);
          b.insert(services, row, onConflict: DoUpdate((old) => row));
        }
      });
    });
    _invalidateSchema(service);
    logger.fine('setLocal for "$service" complete (${items.length} items).');
  }

  /// Replaces the cached collection definitions.
  ///
  /// Reads that need the schema (validation, expand, file fields) wait for
  /// an in-flight [setSchema], so an un-awaited call at startup cannot race
  /// the first writes.
  Future<void> setSchema(List<Map<String, dynamic>> items) {
    final op = _schemaWrite.then((_) => setLocal('schema', items));
    _schemaWrite = op.then((_) {}, onError: (Object _) {});
    return op;
  }

  // -- Server data ---------------------------------------------------------

  static bool _isNewer(Object? server, Object? local) {
    final s = server is String ? DateTime.tryParse(server) : null;
    final l = local is String ? DateTime.tryParse(local) : null;
    if (s == null || l == null) return true;
    return s.isAfter(l);
  }

  static List<String>? _stringList(Object? value) =>
      value is List ? value.whereType<String>().toList() : null;

  /// Writes records returned by the server into the cache.
  ///
  /// Local changes win until they are synced:
  /// - a pending update keeps the fields it changed ([RecordMeta.pendingFields])
  ///   and takes the server values for every other field;
  /// - pending creates, tombstones, local-only rows and pending rows written
  ///   by older versions (no field tracking) are not overwritten.
  ///
  /// [onlyIfNewer] skips synced rows whose cached `updated` is not older than
  /// the server's (list refreshes). [partial] means the items carry a
  /// `fields` projection: they are merged into existing rows and never
  /// inserted, so the cache never holds incomplete records.
  ///
  /// Returns the number of rows written.
  Future<int> upsertServerRecords(
    String service,
    List<Map<String, dynamic>> items, {
    bool onlyIfNewer = false,
    bool partial = false,
  }) =>
      transaction(() async {
        final valid = items
            .where((i) => i['id'] is String && (i['id'] as String).isNotEmpty)
            .toList();
        if (valid.isEmpty) return 0;

        final locals =
            await _rowsByIds(service, valid.map((e) => e['id'] as String));
        final rows = <ServicesCompanion>[];
        final withExpand = <Map<String, dynamic>>[];

        for (final item in valid) {
          final id = item['id'] as String;
          final local = locals[id];
          final server = RecordMeta.strip(item)..remove('expand');
          if (item['expand'] is Map && (item['expand'] as Map).isNotEmpty) {
            withExpand.add(item);
          }

          Map<String, dynamic> next;
          if (local != null && RecordMeta.flag(local[RecordMeta.noSync])) {
            continue;
          } else if (local != null && RecordMeta.isPending(local)) {
            if (RecordMeta.flag(local[RecordMeta.deleted]) ||
                RecordMeta.flag(local[RecordMeta.isNew])) {
              continue;
            }
            final changed = _stringList(local[RecordMeta.pendingFields]);
            if (changed == null) continue;
            next = {
              ...(partial ? local : const <String, dynamic>{}),
              ...server
            };
            for (final field in changed) {
              if (local.containsKey(field)) {
                next[field] = local[field];
              } else {
                next.remove(field);
              }
            }
            for (final key in RecordMeta.keys) {
              if (local.containsKey(key)) next[key] = local[key];
            }
          } else {
            if (partial && local == null) continue;
            if (onlyIfNewer &&
                local != null &&
                !partial &&
                !_isNewer(server['updated'], local['updated'])) {
              continue;
            }
            next = partial && local != null ? {...local, ...server} : server;
            next.removeWhere((k, _) => RecordMeta.keys.contains(k));
            next[RecordMeta.synced] = true;
          }
          rows.add(_row(service, id, next));
        }

        if (rows.isNotEmpty) {
          await batch((b) {
            for (final row in rows) {
              b.insert(services, row, onConflict: DoUpdate((old) => row));
            }
          });
          _invalidateSchema(service);
        }
        for (final item in withExpand) {
          await _cacheExpandedRecords(service, item);
        }
        return rows.length;
      });

  /// Merges records from a list fetch into the cache (see
  /// [upsertServerRecords]). It never deletes rows; use [syncLocal] after a
  /// complete fetch to drop records the server no longer returns.
  Future<void> mergeLocal(
    String service,
    List<Map<String, dynamic>> items, {
    bool partial = false,
  }) async {
    final written = await upsertServerRecords(
      service,
      items,
      onlyIfNewer: true,
      partial: partial,
    );
    logger.fine(
        'mergeLocal for "$service": wrote $written of ${items.length} records.');
  }

  /// Synchronizes local database with server data, including deletion of stale records.
  ///
  /// This method performs a complete sync by:
  /// 1. Merging incoming items (add new, update existing)
  /// 2. Deleting local records that match the filter but weren't in the server response
  ///
  /// Only synced rows are deleted: pending local changes, tombstones and
  /// local-only (`noSync`) rows are kept.
  ///
  /// **Important:** This should only be called after fetching ALL pages of data
  /// (e.g., from getFullList), not for single-page paginated fetches.
  Future<void> syncLocal(
    String service,
    List<Map<String, dynamic>> items, {
    String? filter,
  }) async {
    await mergeLocal(service, items);

    final incomingIds =
        items.map((i) => i['id'] as String?).whereType<String>().toSet();

    if (incomingIds.isEmpty && items.isNotEmpty) {
      logger.warning(
          'syncLocal for "$service": No valid IDs in incoming items, skipping deletion phase');
      return;
    }

    final localRecords = await $query(
      service,
      filter: filter,
      fields: 'id,synced,noSync,deleted',
      includeDeleted: true,
      includeOtherOwners: true,
    ).get();

    final recordsToDelete = <String>[];
    for (final localRecord in localRecords) {
      final localId = localRecord['id'] as String?;
      if (localId == null || incomingIds.contains(localId)) continue;
      final synced = localRecord[RecordMeta.synced];
      if (synced == false || synced == 0) continue;
      if (RecordMeta.flag(localRecord[RecordMeta.noSync])) continue;
      if (RecordMeta.flag(localRecord[RecordMeta.deleted])) continue;
      recordsToDelete.add(localId);
    }

    if (recordsToDelete.isEmpty) {
      logger.fine('syncLocal for "$service": No stale records to delete.');
      return;
    }

    // Safety check: Don't delete everything if server returned empty
    // This protects against server errors causing mass data loss
    if (incomingIds.isEmpty && recordsToDelete.length > 10) {
      logger.warning(
          'syncLocal for "$service": Server returned empty but ${recordsToDelete.length} '
          'local records would be deleted. Skipping deletion as safety measure. '
          'If this is intentional, use deleteAll() instead.');
      return;
    }

    logger.fine(
        'syncLocal for "$service": Deleting ${recordsToDelete.length} stale records '
        '(filter: ${filter ?? "none"})');

    await deleteSyncedRows(service, recordsToDelete);
  }

  // -- Local changes -------------------------------------------------------

  /// Applies a PocketBase request body to [base] the way the server does:
  /// plain keys replace; `field+` / `+field` append / prepend (multi-value
  /// fields) or add (numbers); `field-` removes values or subtracts.
  ///
  /// Returns the new data and the plain names of the fields that changed.
  static ({Map<String, dynamic> data, Set<String> changed}) applyRequestBody(
    CollectionModel? collection,
    Map<String, dynamic> base,
    Map<String, dynamic> body,
  ) {
    final data = Map<String, dynamic>.of(base);
    final changed = <String>{};
    for (final entry in body.entries) {
      final key = entry.key;
      if (RecordMeta.keys.contains(key) || key == 'id') continue;
      if (RecordMeta.systemKeys.contains(key)) continue;

      var name = key;
      var op = '=';
      if (key.startsWith('+')) {
        name = key.substring(1);
        op = 'prepend';
      } else if (key.endsWith('+')) {
        name = key.substring(0, key.length - 1);
        op = 'append';
      } else if (key.endsWith('-')) {
        name = key.substring(0, key.length - 1);
        op = 'subtract';
      }
      final field = collection?.fields.where((f) => f.name == name).firstOrNull;
      if (op != '=' && field == null && !data.containsKey(name)) {
        // Not a modifier of a known field: keep the key as sent.
        name = key;
        op = '=';
      }
      changed.add(name);
      if (op == '=') {
        final value = entry.value;
        final maxSelect = field?.data['maxSelect'];
        final isSingleRef = field != null &&
            const {'select', 'file', 'relation'}.contains(field.type) &&
            !(maxSelect is num && maxSelect > 1);
        // Uploads under a plain key arrive as a list; single-value fields
        // keep the last one, like the server.
        data[name] = isSingleRef && value is List
            ? (value.isEmpty ? '' : value.last)
            : value;
        continue;
      }

      final current = data[name];
      final isNumber =
          field?.type == 'number' || (field == null && current is num);
      if (isNumber) {
        final a = current is num ? current : 0;
        final b = entry.value is num
            ? entry.value as num
            : num.tryParse('${entry.value}') ?? 0;
        data[name] = op == 'subtract' ? a - b : a + b;
        continue;
      }

      final maxSelect = field?.data['maxSelect'];
      final isMulti =
          field == null ? current is List : (maxSelect is num && maxSelect > 1);
      final values =
          entry.value is List ? (entry.value as List).toList() : [entry.value];
      if (!isMulti) {
        if (op == 'subtract') {
          if (values.contains(current)) data[name] = '';
        } else if (values.isNotEmpty) {
          data[name] = values.last;
        }
        continue;
      }
      final list = current is List ? current.toList() : <dynamic>[];
      switch (op) {
        case 'append':
          list.addAll(values);
        case 'prepend':
          list.insertAll(0, values);
        case 'subtract':
          list.removeWhere(values.contains);
      }
      data[name] = list;
    }
    return (data: data, changed: changed);
  }

  /// Writes a locally created record. [sync] false makes it local-only
  /// (`noSync`); otherwise it is queued for the server.
  Future<Map<String, dynamic>> writeLocalCreate(
    String service,
    Map<String, dynamic> body, {
    required bool sync,
    String? owner,
    List<Map<String, String>> files = const [],
  }) async {
    final collection = await collectionByName(service);
    final rawId = body['id'];
    final id = rawId is String && rawId.isNotEmpty ? rawId : newId();
    final applied = applyRequestBody(collection, const {}, body);
    final now = pbTimestamp();
    return $create(service, {
      ...applied.data,
      'id': id,
      'created': now,
      'updated': now,
      RecordMeta.deleted: false,
      RecordMeta.synced: false,
      RecordMeta.isNew: true,
      RecordMeta.noSync: !sync,
      if (sync && owner != null) RecordMeta.pendingOwner: owner,
      if (sync) RecordMeta.pendingRev: 1,
      if (sync && files.isNotEmpty) RecordMeta.pendingFiles: files,
    });
  }

  /// Applies a local update to the cached row [id]. [sync] false makes the
  /// row local-only (`noSync`); otherwise the change is queued.
  ///
  /// File uploads in [files] are tracked for sync but do not mark their
  /// field as changed, so sync appends them instead of overwriting the
  /// field's current server value.
  Future<Map<String, dynamic>> writeLocalUpdate(
    String service,
    String id,
    Map<String, dynamic> body, {
    required bool sync,
    String? owner,
    Map<String, dynamic> fileBody = const {},
    List<Map<String, String>> files = const [],
  }) =>
      transaction(() async {
        final existing = await rowById(service, id);
        final collection = await collectionByName(service);
        final base = existing ?? <String, dynamic>{'id': id};
        final applied = applyRequestBody(collection, base, body);
        final withFiles =
            applyRequestBody(collection, applied.data, fileBody).data;

        final wasPending = existing != null && RecordMeta.isPending(existing);
        if (wasPending) _checkOwner(service, existing, owner);
        final isNew = wasPending && RecordMeta.flag(existing[RecordMeta.isNew]);
        // Pending updates written before field tracking (0.6.x) sync the whole
        // record; tracking only the new fields would drop the older edits.
        final legacy = wasPending &&
            !isNew &&
            !RecordMeta.flag(existing[RecordMeta.deleted]) &&
            existing[RecordMeta.pendingFields] == null;
        final changed = <String>{
          if (wasPending) ...?_stringList(existing[RecordMeta.pendingFields]),
          ...applied.changed,
        };
        final pendingFiles = <Map<String, String>>[
          if (wasPending)
            for (final f
                in (existing[RecordMeta.pendingFiles] as List? ?? const []))
              if (f is Map) {'field': '${f['field']}', 'name': '${f['name']}'},
          ...files,
        ];

        final data = Map<String, dynamic>.of(withFiles)
          ..remove(RecordMeta.retryCount)
          ..remove(RecordMeta.syncError)
          ..remove(RecordMeta.pendingFields)
          ..remove(RecordMeta.pendingFiles)
          ..remove(RecordMeta.pendingOwner);
        data
          ..['id'] = id
          ..['updated'] = pbTimestamp()
          ..[RecordMeta.deleted] = false
          ..[RecordMeta.synced] = false
          ..[RecordMeta.isNew] = isNew
          ..[RecordMeta.noSync] = !sync
          ..[RecordMeta.pendingRev] =
              ((existing?[RecordMeta.pendingRev] as num?)?.toInt() ?? 0) + 1;
        if (sync) {
          if (!isNew && !legacy) {
            data[RecordMeta.pendingFields] = changed.toList();
          }
          if (pendingFiles.isNotEmpty) {
            data[RecordMeta.pendingFiles] = pendingFiles;
          }
          if (owner != null) data[RecordMeta.pendingOwner] = owner;
        }
        return $create(service, data);
      });

  /// Deletes [id] locally. With [sync] the deletion is queued as a tombstone;
  /// a pending create that never reached the server is removed outright,
  /// unless [createInFlight] (its push is running, so the record may exist
  /// on the server by now): then it becomes a tombstone too. A record that
  /// is not cached gets a bare tombstone (id only), so the deletion still
  /// syncs.
  ///
  /// Returns false when the record is not cached and [sync] is false.
  Future<bool> writeLocalDelete(
    String service,
    String id, {
    required bool sync,
    String? owner,
    bool createInFlight = false,
  }) =>
      transaction(() async {
        final existing = await rowById(service, id);
        if (existing == null) {
          if (!sync) return false;
          await $create(
            service,
            {
              'id': id,
              RecordMeta.deleted: true,
              RecordMeta.synced: false,
              RecordMeta.isNew: false,
              RecordMeta.noSync: false,
              RecordMeta.pendingRev: 1,
              if (owner != null) RecordMeta.pendingOwner: owner,
            },
            validate: false,
          );
          return true;
        }
        final wasPending = RecordMeta.isPending(existing);
        if (wasPending) _checkOwner(service, existing, owner);
        final isNew = wasPending && RecordMeta.flag(existing[RecordMeta.isNew]);
        if (sync && isNew && !createInFlight) {
          await $delete(service, id);
          return true;
        }
        final data = Map<String, dynamic>.of(existing)
          ..remove(RecordMeta.retryCount)
          ..remove(RecordMeta.syncError)
          ..remove(RecordMeta.pendingFields);
        data
          ..[RecordMeta.deleted] = true
          ..[RecordMeta.synced] = false
          ..[RecordMeta.isNew] = isNew && !sync
          ..[RecordMeta.noSync] = !sync
          ..[RecordMeta.pendingRev] =
              ((existing[RecordMeta.pendingRev] as num?)?.toInt() ?? 0) + 1;
        if (sync && owner != null) data[RecordMeta.pendingOwner] = owner;
        await $create(service, data, validate: false);
        return true;
      });

  /// Local writes never mix accounts: a pending change queued by another
  /// account (hidden until it logs in again) cannot be edited or deleted.
  static void _checkOwner(
    String service,
    Map<String, dynamic> row,
    String? owner,
  ) {
    final pendingOwner = row[RecordMeta.pendingOwner] as String?;
    if (pendingOwner == null || pendingOwner == owner) return;
    throw StateError(
      '$service/${row['id']} has unsynced changes of another account; '
      'they sync when that account logs in again.',
    );
  }

  /// Replaces the pending row [id] with the server's version after a
  /// successful sync of revision [sentRev] that uploaded [sentFiles]
  /// (`{field, name}` entries of [RecordMeta.pendingFiles]).
  ///
  /// If the row changed while the request was in flight, the newer local
  /// changes stay pending: changed fields keep their local values (names of
  /// the files just uploaded become the server's names), uploads that were
  /// not sent stay queued, and a deletion stays a tombstone.
  Future<void> completePendingSync(
    String service,
    String id,
    int? sentRev,
    Map<String, dynamic> server, {
    List<Map<String, dynamic>> sentFiles = const [],
  }) {
    return transaction(() async {
      final row = await rowById(service, id);
      if (row == null) return;

      final renamed = await _renameUploadedBlobs(id, row, server, sentFiles);
      final serverData = RecordMeta.strip(server)..remove('expand');

      final rev = (row[RecordMeta.pendingRev] as num?)?.toInt();
      final localOnly = RecordMeta.flag(row[RecordMeta.noSync]);
      if (rev == sentRev || (!RecordMeta.isPending(row) && !localOnly)) {
        serverData[RecordMeta.synced] = true;
        await $create(service, {...serverData, 'id': id}, validate: false);
        return;
      }
      // A local-only (`cacheOnly`) change made meanwhile stays as it is.
      if (localOnly) return;

      final owner = row[RecordMeta.pendingOwner];
      final next = <String, dynamic>{
        ...serverData,
        'id': id,
        RecordMeta.synced: false,
        RecordMeta.isNew: false,
        RecordMeta.noSync: false,
        RecordMeta.pendingRev: rev,
        if (owner != null) RecordMeta.pendingOwner: owner,
      };

      if (RecordMeta.flag(row[RecordMeta.deleted])) {
        // Deleted while the record was being pushed: it exists on the
        // server now, so the next push must delete it.
        next[RecordMeta.deleted] = true;
        await $create(service, next, validate: false);
        return;
      }

      Object? local(String field) {
        final value = row[field];
        if (renamed.isEmpty) return value;
        if (value is String) return renamed[value] ?? value;
        if (value is List) return [for (final v in value) renamed[v] ?? v];
        return value;
      }

      // Creates (sent whole) and rows written before field tracking (0.6.x,
      // no pendingFields) keep the fields that still differ from what the
      // server stored; updates keep their changed fields.
      final changed = RecordMeta.flag(row[RecordMeta.isNew])
          ? _fieldsDiffering(row, serverData, local)
          : _stringList(row[RecordMeta.pendingFields]) ??
              _fieldsDiffering(row, serverData, local);
      for (final field in changed) {
        if (row.containsKey(field)) {
          next[field] = local(field);
        } else {
          next.remove(field);
        }
      }

      final sentNames = {for (final f in sentFiles) f['name']};
      final unsent = [
        for (final f in (row[RecordMeta.pendingFiles] as List? ?? const []))
          if (f is Map && !sentNames.contains(f['name'])) f,
      ];
      if (changed.isEmpty && unsent.isEmpty) {
        // The edits made meanwhile equal what the server now has.
        serverData[RecordMeta.synced] = true;
        await $create(service, {...serverData, 'id': id}, validate: false);
        return;
      }
      next
        ..[RecordMeta.deleted] = false
        ..[RecordMeta.pendingFields] = changed;
      if (unsent.isNotEmpty) {
        next[RecordMeta.pendingFiles] = unsent;
        _addPendingFileNames(next, unsent);
      }
      await $create(service, next, validate: false);
    });
  }

  /// Records that the server accepted a write of [id] that set [fields]
  /// (from an online request, not the sync queue) and caches [server].
  ///
  /// A pending local change of the record no longer needs to send those
  /// fields: the request was newer. The rest of the change stays pending.
  Future<void> acceptServerWrite(
    String service,
    String id,
    Map<String, dynamic> server,
    Iterable<String> fields, {
    bool partial = false,
  }) {
    return transaction(() async {
      final row = await rowById(service, id);
      if (row == null ||
          !RecordMeta.isPending(row) ||
          RecordMeta.flag(row[RecordMeta.deleted])) {
        await upsertServerRecords(service, [server], partial: partial);
        return;
      }
      final sent = fields.toSet();
      final serverData = RecordMeta.strip(server)..remove('expand');
      final base = partial ? {...row, ...serverData} : serverData;
      // Creates and rows written before field tracking (0.6.x): every field
      // that differs from the server's version is still to be sent.
      final pendingNow = RecordMeta.flag(row[RecordMeta.isNew])
          ? _fieldsDiffering(row, base, (f) => row[f])
          : _stringList(row[RecordMeta.pendingFields]) ??
              _fieldsDiffering(row, base, (f) => row[f]);
      final remaining = pendingNow.where((f) => !sent.contains(f)).toList();
      final files = row[RecordMeta.pendingFiles] as List? ?? const [];
      if (remaining.isEmpty && files.isEmpty) {
        final next = Map<String, dynamic>.of(base)
          ..removeWhere((k, _) => RecordMeta.keys.contains(k))
          ..['id'] = id
          ..[RecordMeta.synced] = true;
        await $create(service, next, validate: false);
        return;
      }
      final next = Map<String, dynamic>.of(base)
        ..removeWhere((k, _) => RecordMeta.keys.contains(k));
      for (final field in remaining) {
        if (row.containsKey(field)) next[field] = row[field];
      }
      _addPendingFileNames(next, files);
      final owner = row[RecordMeta.pendingOwner];
      next
        ..['id'] = id
        ..[RecordMeta.synced] = false
        ..[RecordMeta.isNew] = false
        ..[RecordMeta.deleted] = false
        ..[RecordMeta.noSync] = false
        ..[RecordMeta.pendingFields] = remaining
        ..[RecordMeta.pendingRev] =
            ((row[RecordMeta.pendingRev] as num?)?.toInt() ?? 0) + 1;
      if (files.isNotEmpty) next[RecordMeta.pendingFiles] = files;
      if (owner != null) next[RecordMeta.pendingOwner] = owner;
      await $create(service, next, validate: false);
    });
  }

  /// Record fields of [row] whose local value ([local] maps file names)
  /// differs from [server].
  static List<String> _fieldsDiffering(
    Map<String, dynamic> row,
    Map<String, dynamic> server,
    Object? Function(String field) local,
  ) =>
      [
        for (final key in row.keys)
          if (!RecordMeta.keys.contains(key) &&
              !RecordMeta.systemKeys.contains(key) &&
              jsonEncode(local(key)) != jsonEncode(server[key]))
            key,
      ];

  /// Adds the local names of queued uploads [files] to their file fields in
  /// [data], so the cached value shows them until they sync.
  static void _addPendingFileNames(
    Map<String, dynamic> data,
    Iterable<dynamic> files,
  ) {
    for (final f in files) {
      if (f is! Map || f['name'] is! String || f['field'] is! String) continue;
      final field = baseFieldName(f['field'] as String);
      final name = f['name'] as String;
      final value = data[field];
      if (value is List) {
        if (!value.contains(name)) data[field] = [...value, name];
      } else if (value is String) {
        data[field] = name;
      }
    }
  }

  /// PocketBase stores uploads as `snake_case(name)_<random>.<ext>`; re-key
  /// the local blobs of the uploaded [sentFiles] to those names. Returns the
  /// local → server name map.
  Future<Map<String, String>> _renameUploadedBlobs(
    String recordId,
    Map<String, dynamic> row,
    Map<String, dynamic> server,
    List<Map<String, dynamic>> sentFiles,
  ) async {
    final renamed = <String, String>{};
    if (sentFiles.isEmpty) return renamed;
    final pendingNames = <String>{
      for (final f in (row[RecordMeta.pendingFiles] as List? ?? const []))
        if (f is Map && f['name'] is String) f['name'] as String,
    };
    final byField = <String, List<String>>{};
    for (final f in sentFiles) {
      if (f['name'] is! String || f['field'] is! String) continue;
      final field = baseFieldName(f['field'] as String);
      byField.putIfAbsent(field, () => []).add(f['name'] as String);
    }
    for (final entry in byField.entries) {
      final before = <String>{
        ..._relationIds(row[entry.key]),
      }.difference(pendingNames);
      final fresh = _relationIds(server[entry.key])
          .where((n) => !before.contains(n))
          .toList();
      for (final local in entry.value) {
        final stem = pbFileStem(local);
        final match =
            fresh.where((n) => n.startsWith('${stem}_')).firstOrNull ??
                fresh.firstOrNull;
        if (match == null) continue;
        fresh.remove(match);
        renamed[local] = match;
        await (update(blobFiles)
              ..where((t) =>
                  t.recordId.equals(recordId) & t.filename.equals(local)))
            .write(BlobFilesCompanion(filename: Value(match)));
      }
    }
    return renamed;
  }

  /// Records a failed sync attempt of revision [sentRev] for the pending row
  /// [id]. With [error] the row is parked (`syncError`) and automatic sync
  /// skips it. Nothing is recorded when the row changed meanwhile: the new
  /// change has not been tried yet. Returns whether the failure was recorded.
  Future<bool> markSyncFailure(
    String service,
    String id, {
    required int? sentRev,
    required int retryCount,
    Map<String, dynamic>? error,
  }) {
    return transaction(() async {
      final row = await rowById(service, id);
      if (row == null || !RecordMeta.isPending(row)) return false;
      if ((row[RecordMeta.pendingRev] as num?)?.toInt() != sentRev) {
        return false;
      }
      final data = Map<String, dynamic>.of(row)
        ..[RecordMeta.retryCount] = retryCount;
      if (error != null) data[RecordMeta.syncError] = error;
      // Keep `updated` so watchers compare by the record's own timestamp.
      await $create(service, data, validate: false);
      return true;
    });
  }

  /// Deletes the rows [ids] of [service] that hold no unsynced or
  /// local-only data (checked and deleted atomically).
  Future<void> deleteSyncedRows(String service, List<String> ids) {
    return transaction(() async {
      final rows = await _rowsByIds(service, ids);
      for (final entry in rows.entries) {
        final row = entry.value;
        if (RecordMeta.isPending(row) ||
            RecordMeta.flag(row[RecordMeta.noSync])) {
          continue;
        }
        await $delete(service, entry.key);
      }
    });
  }

  /// Rows with unsynced local changes (including offline deletions) across
  /// all collections, or only [service], oldest first. Excludes local-only
  /// rows and rows queued by another account. Rows the server rejected carry
  /// [RecordMeta.syncError]. Use `.watch()` for a live pending queue.
  Selectable<Service> pendingRecords({String? service}) {
    return customSelect(
      "SELECT * FROM services WHERE service != 'schema' AND $_pendingSql "
      'AND $_ownerVisibleSql ${service == null ? '' : 'AND service = ? '}'
      'ORDER BY cachedAt, rowid',
      variables: [
        Variable<String>(activeOwner),
        if (service != null) Variable<String>(service),
      ],
      readsFrom: {services},
    ).map((row) => services.map(row.data));
  }

  /// Collections with pending rows the active account may sync now
  /// (excludes rows parked with [RecordMeta.syncError]).
  Future<List<String>> pendingServices() async {
    final rows = await customSelect(
      "SELECT DISTINCT service FROM services WHERE service != 'schema' AND $_pendingSql "
      "AND json_extract(data, '\$.syncError') IS NULL AND $_ownerVisibleSql",
      variables: [Variable<String>(activeOwner)],
      readsFrom: {services},
    ).get();
    return [for (final r in rows) r.read<String>('service')];
  }

  // -- Files ---------------------------------------------------------------

  Selectable<BlobFile> getFile(String recordId, String filename) {
    return select(blobFiles)
      ..where((tbl) =>
          tbl.recordId.equals(recordId) & tbl.filename.equals(filename));
  }

  Future<BlobFile> setFile(
    String recordId,
    String filename,
    Uint8List data, {
    DateTime? expires,
  }) async {
    return transaction(() async {
      await (delete(blobFiles)
            ..where((tbl) =>
                tbl.recordId.equals(recordId) & tbl.filename.equals(filename)))
          .go();
      final item = BlobFilesCompanion.insert(
        filename: filename,
        data: data,
        recordId: recordId,
        expiration: expires != null ? Value(expires) : const Value.absent(),
        created: Value(DateTime.now().toUtc().toIso8601String()),
        updated: Value(DateTime.now().toUtc().toIso8601String()),
      );
      return into(blobFiles).insertReturning(item);
    });
  }

  Future<void> deleteFile(String recordId, String filename) async {
    final q = delete(blobFiles)
      ..where((tbl) =>
          tbl.recordId.equals(recordId) & tbl.filename.equals(filename));
    await q.go();
  }

  /// Returns all cached file blobs for a given record.
  Selectable<BlobFile> getFilesForRecord(String recordId) {
    return select(blobFiles)..where((tbl) => tbl.recordId.equals(recordId));
  }

  // -- Cached responses ----------------------------------------------------

  /// Caches a raw JSON response string against a unique key.
  Future<void> cacheResponse(String key, String jsonData) async {
    final companion = CachedResponsesCompanion.insert(
      requestKey: key,
      responseData: jsonData,
      cachedAt: Value(DateTime.now().toUtc()),
    );
    await into(cachedResponses)
        .insert(companion, mode: InsertMode.insertOrReplace);
  }

  /// Retrieves a cached JSON response string by its key.
  Future<String?> getCachedResponse(String key) async {
    final query = select(cachedResponses)
      ..where((tbl) => tbl.requestKey.equals(key));
    final result = await query.getSingleOrNull();
    return result?.responseData;
  }

  // -- Maintenance ---------------------------------------------------------

  /// Deletes cached server rows that were last written before [cutoffDate].
  ///
  /// Never deletes the schema, pending local changes, tombstones or
  /// local-only (`noSync`) rows. Returns the number of rows deleted.
  Future<int> cleanupExpiredRecords({required DateTime cutoffDate}) async {
    final deleted = await customUpdate(
      "DELETE FROM services WHERE service != 'schema' "
      'AND cachedAt IS NOT NULL AND cachedAt < ? '
      "AND COALESCE(json_extract(data, '\$.synced'), 1) = 1 "
      "AND COALESCE(json_extract(data, '\$.noSync'), 0) = 0 "
      'AND $_notDeletedSql',
      variables: [Variable<DateTime>(cutoffDate)],
      updates: {services},
      updateKind: UpdateKind.delete,
    );
    if (deleted > 0) {
      logger.info(
          'Cleaned up $deleted expired records (cached before $cutoffDate)');
    }
    return deleted;
  }

  /// Deletes cached responses that were cached before [cutoffDate].
  Future<int> cleanupExpiredResponses({required DateTime cutoffDate}) async {
    final result = await (delete(cachedResponses)
          ..where((tbl) => tbl.cachedAt.isSmallerThanValue(cutoffDate)))
        .go();

    if (result > 0) {
      logger.info('Cleaned up $result expired cached responses');
    }
    return result;
  }

  /// Deletes file blobs past their expiration date and, when [orphanCutoff]
  /// is given, blobs created before it whose record is no longer cached.
  Future<int> cleanupExpiredFiles({DateTime? orphanCutoff}) async {
    final now = DateTime.now().toUtc();
    var result = await (delete(blobFiles)
          ..where((tbl) => tbl.expiration.isSmallerThanValue(now)))
        .go();
    if (orphanCutoff != null) {
      final cutoff = orphanCutoff.toUtc().toIso8601String();
      result += await (delete(blobFiles)
            ..where((tbl) =>
                tbl.created.isSmallerThanValue(cutoff) &
                tbl.recordId.isNotInQuery(
                    selectOnly(services)..addColumns([services.id]))))
          .go();
    }

    if (result > 0) {
      logger.info('Cleaned up $result expired file blobs');
    }
    return result;
  }

  /// Deletes cached server data, cached responses and file blobs; keeps the
  /// schema. With [keepPending] (the default) unsynced local changes and
  /// their blobs are kept so they can still sync after the next login.
  Future<void> clearCache({bool keepPending = true}) async {
    await transaction(() async {
      await customUpdate(
        "DELETE FROM services WHERE service != 'schema'"
        '${keepPending ? ' AND NOT $_pendingSql' : ''}',
        updates: {services},
        updateKind: UpdateKind.delete,
      );
      await (delete(blobFiles)
            ..where((tbl) => tbl.recordId.isNotInQuery(selectOnly(services)
              ..addColumns([services.id])
              ..where(services.service.isNotValue('schema')))))
          .go();
      await delete(cachedResponses).go();
    });
    logger.info('Local cache cleared (keepPending: $keepPending).');
  }

  /// Deletes everything except the schema, including unsynced changes.
  Future<void> clearAllData() => clearCache(keepPending: false);
}

/// A [Selectable] that post-processes the complete result list (used for
/// batched relation expansion instead of per-row lookups).
class _ExpandedSelectable extends Selectable<Map<String, dynamic>> {
  _ExpandedSelectable(this._rows, this._expand);

  final Selectable<Map<String, dynamic>> _rows;
  final Future<List<Map<String, dynamic>>> Function(List<Map<String, dynamic>>)
      _expand;

  @override
  Future<List<Map<String, dynamic>>> get() async => _expand(await _rows.get());

  @override
  Stream<List<Map<String, dynamic>>> watch() => _rows.watch().asyncMap(_expand);
}
