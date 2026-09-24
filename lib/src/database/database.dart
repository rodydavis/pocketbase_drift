import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:logging/logging.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:pocketbase_drift/src/database/filter_parser.dart';

import 'tables.dart';

part 'database.g.dart';

@DriftDatabase(
  tables: [Services, BlobFiles, CachedResponses],
  include: {'sql/search.drift'},
)
class DataBase extends _$DataBase {
  DataBase(super.e) {
    logger = Logger('PocketBaseDrift.db');
  }

  late final Logger logger;

  /// Extracts the 'updated' timestamp from a record
  static String _getUpdatedTimestamp(Map<String, dynamic> data) {
    final updated = data['updated'];
    if (updated is String && updated.isNotEmpty) return updated;
    return DateTime.now().toUtc().toIso8601String().replaceFirst('T', ' ');
  }

  /// Extracts the 'created' timestamp from a record
  static String _getCreatedTimestamp(Map<String, dynamic> data) {
    final created = data['created'];
    if (created is String && created.isNotEmpty) return created;
    return DateTime.now().toUtc().toIso8601String().replaceFirst('T', ' ');
  }

  @override
  int get schemaVersion => 3;

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
      },
    );
  }

  Selectable<Service> search(String query, {String? service}) {
    if (service != null) {
      return _searchService(query, service).map((p0) => p0.record);
    } else {
      return _search(query).map((p0) => p0.record);
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

    if (filter != null && filter.isNotEmpty) {
      // Delegate all filter parsing to the new robust parser.
      final parser = FilterParser(filter, baseFields: baseFields);
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
            sb.write(fixField(part.substring(1).trim(),
                alias: false)); // Apply fixField for sorting
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
      ).map(parseRow);
      return query.map(CollectionModel.fromJson);
    } else {
      final query = customSelect(
        "SELECT * FROM services WHERE service = 'schema'",
      ).map(parseRow);
      return query.map(CollectionModel.fromJson);
    }
  }

  /// Queries records for a service.
  ///
  /// By default records that were deleted offline and still await server
  /// sync (tombstones, `deleted: true`) are excluded. Internal callers that
  /// operate on the pending-sync queue pass [includeDeleted]: true.
  Selectable<Map<String, dynamic>> $query(
    String service, {
    String? expand,
    String? fields,
    String? filter,
    String? sort,
    int? offset,
    int? limit,
    bool includeDeleted = false,
  }) {
    final (query, variables) = queryBuilder(
      service,
      fields: fields,
      filter: filter,
      sort: sort,
      offset: offset,
      limit: limit,
      includeDeleted: includeDeleted,
    );
    logger.finer('query: $query, variables: $variables');
    return customSelect(
      query,
      variables: variables,
      readsFrom: {services},
    ).asyncMap((r) async {
      final record = parseRow(r);
      return record; // Return early if no expand is needed
    }).asyncMap((initialRecords) async {
      // --- BATCHED EXPAND LOGIC ---
      if (expand == null || expand.isEmpty) {
        return initialRecords;
      }

      final records = [initialRecords]; // Process as a list
      final targets = expand.split(',').map((e) => e.trim()).toList();
      final allCollections = await $collections().get();

      // 1. COLLECT all relation data and IDs needed
      final relationsToFetch =
          <String, Set<String>>{}; // eg: 'relation_field' -> {'id1', 'id2'}
      // Track metadata including whether this is a single relation (maxSelect == 1)
      final relationMeta = <String,
          ({String collectionName, String nestedExpand, bool isSingle})>{};

      for (final target in targets) {
        final levels = target.split('.');
        final targetField = levels.first;
        if (targetField.contains('(') && targetField.contains(')')) {
          throw UnimplementedError('Indirect expand not supported yet');
        }
        if (levels.length > 6) throw Exception('Max 6 levels expand supported');

        // Get metadata for this relation
        final currentCollectionSchema =
            allCollections.firstWhere((c) => c.name == service);
        final schemaField = currentCollectionSchema.fields
            .firstWhere((f) => f.name == targetField);
        final targetCollectionId = schemaField.data['collectionId'] as String?;
        if (targetCollectionId == null) continue;
        final targetCollection =
            allCollections.firstWhere((c) => c.id == targetCollectionId);

        // Determine if this is a single relation (maxSelect <= 1 per PocketBase docs)
        final maxSelect = schemaField.data['maxSelect'];
        final isSingle = maxSelect == null || maxSelect <= 1;

        relationMeta[targetField] = (
          collectionName: targetCollection.name,
          nestedExpand: levels.length > 1 ? levels.skip(1).join('.') : '',
          isSingle: isSingle,
        );
        relationsToFetch.putIfAbsent(targetField, () => <String>{});

        // Collect all unique IDs for this relation from all records
        for (final record in records) {
          final dynamic relatedIdsRaw = record[targetField];
          if (relatedIdsRaw is String && relatedIdsRaw.isNotEmpty) {
            relationsToFetch[targetField]!.add(relatedIdsRaw);
          } else if (relatedIdsRaw is List) {
            for (final id in relatedIdsRaw
                .whereType<String>()
                .where((id) => id.isNotEmpty)) {
              relationsToFetch[targetField]!.add(id);
            }
          }
        }
      }

      // 2. FETCH all related records in batches
      final fetchedRelations = <String,
          Map<
              String,
              Map<String,
                  dynamic>>>{}; // 'relation_field' -> {'id1' -> {record_data}}
      for (final entry in relationsToFetch.entries) {
        final relationName = entry.key;
        final ids = entry.value;
        if (ids.isEmpty) continue;

        final meta = relationMeta[relationName]!;
        final idFilter = "(${ids.map((id) => "id = '$id'").join(' OR ')})";

        final relatedRecords = await $query(
          meta.collectionName,
          expand: meta.nestedExpand,
          filter: idFilter,
        ).get();

        fetchedRelations.putIfAbsent(relationName, () => {});
        for (final relatedRecord in relatedRecords) {
          fetchedRelations[relationName]![relatedRecord['id'] as String] =
              relatedRecord;
        }
      }

      // 3. ATTACH fetched records to the main records
      // Use dynamic type for expand map to support both single objects and lists
      for (final record in records) {
        record['expand'] = <String, dynamic>{};
        for (final relationName in targets.map((t) => t.split('.').first)) {
          final results = <Map<String, dynamic>>[];
          final dynamic relatedIdsRaw = record[relationName];
          final fetchedData = fetchedRelations[relationName] ?? {};
          final meta = relationMeta[relationName];

          if (relatedIdsRaw is String && relatedIdsRaw.isNotEmpty) {
            if (fetchedData.containsKey(relatedIdsRaw)) {
              results.add(fetchedData[relatedIdsRaw]!);
            }
          } else if (relatedIdsRaw is List) {
            for (final id in relatedIdsRaw
                .whereType<String>()
                .where((id) => id.isNotEmpty)) {
              if (fetchedData.containsKey(id)) {
                results.add(fetchedData[id]!);
              }
            }
          }

          // Match PocketBase SDK behavior:
          // - Single relations (maxSelect == 1): return the object directly or null
          // - Multi relations: return the list
          if (meta != null && meta.isSingle) {
            record['expand'][relationName] =
                results.isEmpty ? null : results.first;
          } else {
            record['expand'][relationName] = results;
          }
        }
      }

      return records.first;
    }); // Use .first since we are mapping from a single record
  }

  Future<int> $count(String service) async {
    final (query, variables) = queryBuilder(
      service,
      fields: 'COUNT(*)',
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

  Future<Map<String, dynamic>> $create(
    String service,
    Map<String, dynamic> data, {
    bool validate = true,
  }) async {
    if (data['id'] == '') data.remove('id');
    final id = data['id'] as String?;

    final mutableData = Map<String, dynamic>.from(data);
    mutableData.remove('id');

    if (validate && service != 'schema') {
      final collection = await $collections(service: service).getSingleOrNull();
      if (collection == null) {
        throw Exception(
          'Failed to validate data for service "$service": Collection schema not found in local database. Ensure schemas are loaded before creating/updating records.',
        );
      }
      validateData(collection, mutableData);
    }

    final String created = _getCreatedTimestamp(data);
    final String updated = _getUpdatedTimestamp(data);

    final item = ServicesCompanion.insert(
      id: id != null ? Value(id) : const Value.absent(),
      service: service,
      data: data,
      created: Value(created),
      updated: Value(updated),
    );

    // The insertReturning method gives us the final state of the row.
    // We can use it directly instead of re-querying the database.
    final insertedService = await into(services).insertReturning(
      item,
      onConflict: DoUpdate((old) => item),
    );

    // Cache any expanded related records to their respective collections
    // This ensures they're available when those collections are queried directly
    await _cacheExpandedRecords(service, data);

    // Manually construct the final map, which is what `parseRow` and `$query`
    // would have done. This is more efficient and avoids the race condition.
    final finalData = <String, dynamic>{
      ...insertedService.data,
      'id': insertedService.id,
      'created': insertedService.created,
      'updated': insertedService.updated,
    };
    return finalData;
  }

  /// Recursively cache expanded records to their respective collection tables.
  /// This ensures that when a record is fetched with expand, the related records
  /// are also stored in the local database and can be queried independently.
  Future<void> _cacheExpandedRecords(
    String parentService,
    Map<String, dynamic> data,
  ) async {
    final expand = data['expand'];

    if (expand == null || expand is! Map<String, dynamic>) return;

    // Get the schema for the parent collection to find relation field metadata
    final collection =
        await $collections(service: parentService).getSingleOrNull();
    if (collection == null) {
      return;
    }

    // Build a map of relation field names to their target collection IDs
    final relationFields = <String, String>{};
    for (final field in collection.fields) {
      if (field.type == 'relation') {
        final targetCollectionId = field.data['collectionId'] as String?;
        if (targetCollectionId != null) {
          relationFields[field.name] = targetCollectionId;
        }
      }
    }

    // Get all collections to resolve collection IDs to names
    final allCollections = await $collections().get();
    final collectionIdToName = {
      for (final c in allCollections) c.id: c.name,
    };

    // Process each expanded relation
    for (final entry in expand.entries) {
      final relationName = entry.key;
      final expandedData = entry.value;

      // Find the target collection for this relation
      final targetCollectionId = relationFields[relationName];
      if (targetCollectionId == null) continue;

      final targetCollectionName = collectionIdToName[targetCollectionId];
      if (targetCollectionName == null) continue;

      // Handle both single object and list of objects
      final recordsToCache = <Map<String, dynamic>>[];
      if (expandedData is Map<String, dynamic>) {
        recordsToCache.add(expandedData);
      } else if (expandedData is List) {
        for (final item in expandedData) {
          if (item is Map<String, dynamic>) {
            recordsToCache.add(item);
          }
        }
      }

      // Cache each expanded record to its collection
      for (final record in recordsToCache) {
        if (record['id'] == null) continue;

        // Remove the expand field before saving to avoid storing stale expand data
        // The expand will be re-computed when the record is queried with expand
        final recordToSave = Map<String, dynamic>.from(record);
        recordToSave.remove('expand');

        try {
          // Use internal insert to avoid validation (the data came from server)
          final recordId = recordToSave['id'] as String?;
          if (recordId == null) continue;

          final created = _getCreatedTimestamp(recordToSave);
          final updated = _getUpdatedTimestamp(recordToSave);

          final item = ServicesCompanion.insert(
            id: Value(recordId),
            service: targetCollectionName,
            data: recordToSave,
            created: Value(created),
            updated: Value(updated),
          );

          await into(services).insert(
            item,
            onConflict: DoUpdate((old) => item),
          );

          // Recursively cache any nested expanded records
          if (record['expand'] != null) {
            await _cacheExpandedRecords(targetCollectionName, record);
          }
        } catch (e) {
          logger.fine('Error caching expanded record: $e');
        }
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
    // For updates with validation enabled, we need to merge with existing data
    // to ensure all required fields are present during validation
    if (validate && service != 'schema') {
      // Fetch the existing record
      final existingRecords = await $query(
        service,
        filter: 'id = "$id"',
        limit: 1,
        includeDeleted: true,
      ).get();

      if (existingRecords.isNotEmpty) {
        final existingData = existingRecords.first;
        // Merge existing data with update data (update data takes precedence)
        // This ensures required fields from the existing record are present
        final mergedData = <String, dynamic>{
          ...existingData,
          ...data,
          'id': id, // Ensure ID is always set
        };

        // If 'updated' field wasn't explicitly provided in the update,
        // we generate a new one since this is a local mutation.
        if (!data.containsKey('updated') ||
            data['updated'] == null ||
            data['updated'] == '') {
          mergedData['updated'] =
              DateTime.now().toUtc().toIso8601String().replaceFirst('T', ' ');
        }

        return $create(
          service,
          mergedData,
          validate: validate,
        );
      }
    }

    // Fallback: If no existing record found or validation is disabled
    final fallbackData = <String, dynamic>{...data, 'id': id};
    if (!data.containsKey('updated') ||
        data['updated'] == null ||
        data['updated'] == '') {
      fallbackData['updated'] =
          DateTime.now().toUtc().toIso8601String().replaceFirst('T', ' ');
    }

    return $create(
      service,
      fallbackData,
      validate: validate,
    );
  }

  Future<void> $delete(
    String service,
    String id, {
    Batch? batch,
  }) async {
    // If a batch is provided, we can't perform the file lookup and delete here.
    // This is a limitation of batching; file cleanup will only happen for non-batched deletes.
    // For most app logic (like sync), deletes are not batched, so this is acceptable.
    if (batch != null) {
      batch.deleteWhere(
        services,
        (r) => r.service.equals(service) & r.id.equals(id),
      );
      return;
    }

    // Use a transaction to ensure both record and its files are deleted atomically.
    await transaction(() async {
      // 1. Find the record to get its data before deleting.
      final recordToDelete = await (select(services)
            ..where((r) => r.service.equals(service))
            ..where((r) => r.id.equals(id)))
          .getSingleOrNull();

      if (recordToDelete != null) {
        // 2. Get the collection schema to identify file fields.
        final collection =
            await $collections(service: service).getSingleOrNull();
        if (collection != null) {
          final fileFields = collection.fields.where((f) => f.type == 'file');

          for (final field in fileFields) {
            final dynamic filenames = recordToDelete.data[field.name];
            if (filenames == null) continue;

            // 3. Delete each file from the blobFiles table.
            if (filenames is String && filenames.isNotEmpty) {
              await deleteFile(id, filenames);
            } else if (filenames is List) {
              for (final filename in filenames.whereType<String>()) {
                await deleteFile(id, filename);
              }
            }
          }
        }
      }

      // 4. Delete the main record itself.
      await (delete(services)
            ..where((r) => r.service.equals(service))
            ..where((r) => r.id.equals(id)))
          .go();
    });
  }

  Future<void> deleteAll(
    String service, {
    List<String>? ids,
  }) async {
    if (ids != null) {
      return batch((b) async {
        for (final id in ids) {
          await $delete(service, id, batch: b);
        }
      });
    } else {
      final query = delete(services)..where((r) => r.service.equals(service));
      await query.go();
    }
  }

  Future<void> setLocal(
    String service,
    List<Map<String, dynamic>> items, {
    bool removeAll = true,
  }) async {
    if (removeAll) {
      await (delete(services)..where((r) => r.service.equals(service))).go();
    }

    // Add all
    await batch((b) async {
      for (final item in items) {
        // A record without an ID is invalid and cannot be stored.
        final id = item['id'] as String?;
        if (id == null || id.isEmpty) {
          logger.warning(
              'Skipping record in setLocal for service "$service" due to missing ID: $item');
          continue;
        }

        final createdStr = _getCreatedTimestamp(item);
        final updatedStr = _getUpdatedTimestamp(item);

        final row = ServicesCompanion.insert(
          id: Value(id),
          data: item,
          service: service,
          created: Value(createdStr),
          updated: Value(updatedStr),
        );
        b.insert(
          services,
          row,
          onConflict: DoUpdate((old) => row),
        );
      }
    });
    // Get all
    final query = select(services)..where((tbl) => tbl.service.equals(service));
    final results = await query.get();
    logger.fine(
        'setLocal for "$service" complete. Total items: ${results.length}');
  }

  Future<void> setSchema(List<Map<String, dynamic>> items) =>
      setLocal('schema', items);

  // -- Files --

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
    final existing = await getFile(recordId, filename).get();
    await batch((batch) {
      for (final item in existing) {
        batch.deleteWhere(blobFiles, (tbl) => tbl.rowId.equals(item.id));
      }
    });
    final item = BlobFilesCompanion.insert(
      filename: filename,
      data: data,
      recordId: recordId,
      expiration: expires != null ? Value(expires) : const Value.absent(),
      created: Value(DateTime.now().toUtc().toIso8601String()),
      updated: Value(DateTime.now().toUtc().toIso8601String()),
    );
    return await into(blobFiles).insertReturning(
      item,
      onConflict: DoUpdate((old) => item),
    );
  }

  Future<void> deleteFile(String recordId, String filename) async {
    final q = delete(blobFiles)
      ..where((tbl) =>
          tbl.recordId.equals(recordId) & tbl.filename.equals(filename));
    await q.go();
  }

  /// Returns all cached file blobs for a given record.
  ///
  /// This is useful for syncing files when a record created offline
  /// needs to be uploaded to the server.
  Selectable<BlobFile> getFilesForRecord(String recordId) {
    return select(blobFiles)..where((tbl) => tbl.recordId.equals(recordId));
  }

  /// Intelligently merges a list of items into the local database for a given service.
  ///
  /// This method is more efficient than `setLocal` for list updates because it
  /// only writes records that are new or have a more recent 'updated' timestamp
  /// than their local counterparts.
  ///
  /// **Important**: This method does NOT delete records that exist locally but
  /// are missing from the `items` list. Use [syncLocal] for full synchronization
  /// that includes deletion of stale records.
  Future<void> mergeLocal(
    String service,
    List<Map<String, dynamic>> items,
  ) async {
    if (items.isEmpty) return;

    // 1. Get IDs of incoming items
    final itemIds =
        items.map((i) => i['id'] as String?).whereType<String>().toList();
    if (itemIds.isEmpty) return;

    // 2. Fetch existing local records for these IDs
    final localRecordsMap = <String, Map<String, dynamic>>{};
    const chunkSize =
        100; // SQLite can handle about this many variables in a query.
    for (var i = 0; i < itemIds.length; i += chunkSize) {
      final chunk = itemIds.sublist(
          i, i + chunkSize > itemIds.length ? itemIds.length : i + chunkSize);
      if (chunk.isEmpty) continue;

      final idFilter = "(${chunk.map((id) => "id = '$id'").join(' OR ')})";
      final localRecords = await $query(
        service,
        filter: idFilter,
        fields: 'id, updated, deleted',
        includeDeleted: true,
      ).get();
      for (final r in localRecords) {
        localRecordsMap[r['id'] as String] = r;
      }
    }

    // 3. Identify records to be inserted or updated
    final recordsToWrite = <Map<String, dynamic>>[];
    for (final item in items) {
      final itemId = item['id'] as String?;
      if (itemId == null) continue;

      final localRecord = localRecordsMap[itemId];
      // json_extract returns SQLite integers for JSON booleans when a fields
      // projection is used, so accept both true and 1.
      final localDeleted =
          localRecord != null && (localRecord['deleted'] == true || localRecord['deleted'] == 1);
      if (localDeleted) {
        // The record was deleted offline and the deletion is still pending
        // sync. Keep the tombstone; the sync engine will propagate the
        // deletion. Otherwise stale server data would resurrect the record.
        logger.finer(
            'mergeLocal for "$service": Keeping pending-delete tombstone $itemId');
        continue;
      }
      if (localRecord == null) {
        // It's a new record, so add it.
        recordsToWrite.add(item);
      } else {
        // It's an existing record, check if it's updated.
        final networkUpdatedStr = _getUpdatedTimestamp(item);
        final networkUpdated = DateTime.tryParse(networkUpdatedStr);
        final localUpdated = DateTime.tryParse(localRecord['updated']);

        if (networkUpdated != null &&
            localUpdated != null &&
            networkUpdated.isAfter(localUpdated)) {
          // The network version is newer.
          recordsToWrite.add(item);
        } else if (networkUpdated != null && localUpdated == null) {
          // Local record has no timestamp, so update it.
          recordsToWrite.add(item);
        }
      }
    }

    if (recordsToWrite.isEmpty) {
      logger.fine(
          'mergeLocal for "$service": No new or updated records to write.');
      return;
    }
    logger.fine(
        'mergeLocal for "$service": Writing ${recordsToWrite.length} new/updated records.');

    // 4. Batch write only the necessary records using an upsert.
    await batch((b) {
      for (final item in recordsToWrite) {
        final id = item['id'] as String;
        final createdStr = _getCreatedTimestamp(item);
        final updatedStr = _getUpdatedTimestamp(item);

        final row = ServicesCompanion.insert(
          id: Value(id),
          data: item,
          service: service,
          created: Value(createdStr),
          updated: Value(updatedStr),
        );
        b.insert(services, row, onConflict: DoUpdate((old) => row));
      }
    });

    // Cache any expanded related records to their respective collections
    // This ensures they're available when those collections are queried directly
    for (final item in recordsToWrite) {
      if (item['expand'] != null) {
        await _cacheExpandedRecords(service, item);
      }
    }
  }

  /// Synchronizes local database with server data, including deletion of stale records.
  ///
  /// This method performs a complete sync by:
  /// 1. Merging incoming items (add new, update existing)
  /// 2. Deleting local records that match the filter but weren't in the server response
  ///
  /// **Filter-Aware Deletion Logic:**
  /// When a filter is provided, this method queries the local cache with the SAME filter
  /// and only deletes records that:
  /// - Match the filter locally (would have been returned if still valid)
  /// - Were NOT in the server response
  /// - Are NOT pending local changes (synced != false)
  ///
  /// This correctly handles scenarios like:
  /// - Deleted posts in a community feed
  /// - Removed items from a filtered list
  /// - Records that no longer match filter criteria
  ///
  /// **Important:** This should only be called after fetching ALL pages of data
  /// (e.g., from getFullList), not for single-page paginated fetches.
  ///
  /// Example:
  /// ```dart
  /// // Sync all posts from community X - will delete stale posts for this community
  /// await db.syncLocal('posts', serverPosts, filter: "community = 'communityX'");
  ///
  /// // Unfiltered sync - will delete any stale records in the collection
  /// await db.syncLocal('todos', allTodosFromServer);
  /// ```
  Future<void> syncLocal(
    String service,
    List<Map<String, dynamic>> items, {
    String? filter,
  }) async {
    // 1. First, merge the incoming items (handles add/update)
    await mergeLocal(service, items);

    // 2. Get the IDs of records returned by the server
    final incomingIds =
        items.map((i) => i['id'] as String?).whereType<String>().toSet();

    // 3. Edge case: If server returned items but none had valid IDs, something's wrong
    if (incomingIds.isEmpty && items.isNotEmpty) {
      logger.warning(
          'syncLocal for "$service": No valid IDs in incoming items, skipping deletion phase');
      return;
    }

    // 4. Query local records with the SAME filter
    // This is the key insight: we only consider records that WOULD have been
    // returned by the server if they still existed/matched the criteria
    final localRecords = await $query(
      service,
      filter: filter,
      includeDeleted: true,
    ).get();

    // 5. Find records to delete:
    // - Match the filter (are in localRecords)
    // - Were NOT returned by server (not in incomingIds)
    // - Are synced (not pending local changes we haven't pushed yet)
    // - Are not marked as local-only (noSync != true)
    final recordsToDelete = <String>[];
    for (final localRecord in localRecords) {
      final localId = localRecord['id'] as String?;
      if (localId == null) continue;

      // Skip if the record was in the server response
      if (incomingIds.contains(localId)) continue;

      // Skip records that haven't been synced yet (local creates/updates pending)
      final synced = localRecord['synced'];
      if (synced == false) {
        logger.finer(
            'syncLocal for "$service": Keeping unsynced record $localId');
        continue;
      }

      // Skip local-only records
      final noSync = localRecord['noSync'];
      if (noSync == true) {
        logger.finer(
            'syncLocal for "$service": Keeping local-only record $localId');
        continue;
      }

      // Skip records marked for local deletion (will be handled by retry)
      final deleted = localRecord['deleted'];
      if (deleted == true) {
        logger.finer(
            'syncLocal for "$service": Keeping pending-delete record $localId');
        continue;
      }

      recordsToDelete.add(localId);
    }

    if (recordsToDelete.isEmpty) {
      logger.fine('syncLocal for "$service": No stale records to delete.');
      return;
    }

    // 6. Safety check: Don't delete everything if server returned empty
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

    // 7. Delete the stale records
    await batch((b) {
      for (final id in recordsToDelete) {
        $delete(service, id, batch: b);
      }
    });
  }

  /// Caches a raw JSON response string against a unique key.
  Future<void> cacheResponse(String key, String jsonData) async {
    final companion = CachedResponsesCompanion.insert(
      requestKey: key,
      responseData: jsonData,
      cachedAt: Value(DateTime.now().toUtc()),
    );
    // Use insertOrReplace to handle updates to an existing cached item.
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

  /// Deletes synced records that haven't been updated since [cutoffDate].
  ///
  /// This only removes records that:
  /// - Are marked as synced (not pending local changes)
  /// - Have an `updated` timestamp older than the cutoff
  /// - Are not marked as local-only (noSync)
  ///
  /// Returns the number of records deleted.
  ///
  /// Example:
  /// ```dart
  /// // Delete records older than 60 days
  /// final deleted = await db.cleanupExpiredRecords(
  ///   cutoffDate: DateTime.now().subtract(Duration(days: 60)),
  /// );
  /// ```
  Future<int> cleanupExpiredRecords({required DateTime cutoffDate}) async {
    final cutoffString = cutoffDate.toIso8601String();

    // First count how many will be deleted
    final countResult = await customSelect(
      '''
      SELECT COUNT(*) as count FROM services
      WHERE updated < ?
        AND json_extract(data, '\$.synced') = 1
        AND (json_extract(data, '\$.noSync') IS NULL OR json_extract(data, '\$.noSync') = 0)
        AND (json_extract(data, '\$.deleted') IS NULL OR json_extract(data, '\$.deleted') = 0)
      ''',
      variables: [Variable<String>(cutoffString)],
    ).getSingle();
    final deletedCount = countResult.read<int>('count');

    if (deletedCount > 0) {
      // Only delete records that are:
      // 1. Synced (synced = true)
      // 2. Not local-only (noSync is null or false)
      // 3. Not marked for deletion (deleted = false or null)
      // 4. Updated before the cutoff date
      await customStatement(
        '''
        DELETE FROM services
        WHERE updated < ?
          AND json_extract(data, '\$.synced') = 1
          AND (json_extract(data, '\$.noSync') IS NULL OR json_extract(data, '\$.noSync') = 0)
          AND (json_extract(data, '\$.deleted') IS NULL OR json_extract(data, '\$.deleted') = 0)
        ''',
        [cutoffString],
      );
      logger.info(
          'Cleaned up $deletedCount expired records (older than $cutoffString)');
    }
    return deletedCount;
  }

  /// Deletes cached responses that were cached before [cutoffDate].
  ///
  /// Returns the number of cached responses deleted.
  ///
  /// Example:
  /// ```dart
  /// // Delete cached responses older than 30 days
  /// final deleted = await db.cleanupExpiredResponses(
  ///   cutoffDate: DateTime.now().subtract(Duration(days: 30)),
  /// );
  /// ```
  Future<int> cleanupExpiredResponses({required DateTime cutoffDate}) async {
    final result = await (delete(cachedResponses)
          ..where((tbl) => tbl.cachedAt.isSmallerThanValue(cutoffDate)))
        .go();

    if (result > 0) {
      logger.info('Cleaned up $result expired cached responses');
    }
    return result;
  }

  /// Deletes expired file blobs that have passed their expiration date.
  ///
  /// Returns the number of file blobs deleted.
  Future<int> cleanupExpiredFiles() async {
    final now = DateTime.now().toUtc();
    final result = await (delete(blobFiles)
          ..where((tbl) => tbl.expiration.isSmallerThanValue(now)))
        .go();

    if (result > 0) {
      logger.info('Cleaned up $result expired file blobs');
    }
    return result;
  }

  Future<void> clearAllData() async {
    // Don't clear the schema
    await transaction(() async {
      await (delete(services)..where((r) => r.service.isNotValue('schema')))
          .go();
      await delete(blobFiles).go();
      await delete(cachedResponses).go();
    });
    logger.info('All local data has been cleared.');
  }
}

// extension StringUtils on String {
//   List<String> multiSplit(Iterable<String> delimiters) => delimiters.isEmpty
//       ? [this]
//       : split(RegExp(delimiters.map(RegExp.escape).join('|')));
// }
