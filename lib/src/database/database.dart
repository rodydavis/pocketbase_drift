import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:logging/logging.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:pocketbase_drift/src/database/filter_parser.dart';

import 'tables.dart';

part 'database.g.dart';

@DriftDatabase(
  tables: [Services, BlobFiles],
  include: {'sql/search.drift'},
)
class DataBase extends _$DataBase {
  DataBase(super.e) {
    logger = Logger('PocketBaseDrift.db');
  }

  late final Logger logger;

  @override
  int get schemaVersion => 2;

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

  String queryBuilder(
    String service, {
    String? fields,
    String? filter,
    String? sort,
    int? offset,
    int? limit,
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
    sb.write(" WHERE service = '$service'");

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
      sb.write(' LIMIT $limit');
    }
    if (offset != null) {
      sb.write(' OFFSET $offset');
    }
    return sb.toString();
  }

  Selectable<CollectionModel> $collections({
    String? service,
  }) {
    var str = "SELECT * FROM services WHERE service = 'schema'";
    if (service != null) {
      str += " AND json_extract(services.data, '\$.name') = '$service'";
    }
    final query = customSelect(str).map(parseRow);
    return query.map(CollectionModel.fromJson);
  }

  Selectable<Map<String, dynamic>> $query(
    String service, {
    String? expand,
    String? fields,
    String? filter,
    String? sort,
    int? offset,
    int? limit,
  }) {
    final query = queryBuilder(
      service,
      fields: fields,
      filter: filter,
      sort: sort,
      offset: offset,
      limit: limit,
    );
    logger.finer('query: $query');
    return customSelect(
      query,
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
      final relationMeta =
          <String, ({String collectionName, String nestedExpand})>{};

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

        relationMeta[targetField] = (
          collectionName: targetCollection.name,
          nestedExpand: levels.length > 1 ? levels.skip(1).join('.') : '',
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
      for (final record in records) {
        record['expand'] = <String, List<Map<String, dynamic>>>{};
        for (final relationName in targets.map((t) => t.split('.').first)) {
          final results = <Map<String, dynamic>>[];
          final dynamic relatedIdsRaw = record[relationName];
          final fetchedData = fetchedRelations[relationName] ?? {};

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
          record['expand'][relationName] = results;
        }
      }

      return records.first;
    }); // Use .first since we are mapping from a single record
  }

  Future<int> $count(String service) async {
    final query = queryBuilder(
      service,
      fields: 'COUNT(*)',
    );
    final result = await customSelect(
      query,
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
          final maxSelect = field.data['maxSelect'];
          if (maxSelect != null && maxSelect == 1) {
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

    String date(String key) {
      final value = data[key];
      if (value is String) return value;
      return DateTime.now().toIso8601String();
    }

    final String created = date('created');
    final String updated = date('updated');

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

  Future<Map<String, dynamic>> $update(
    String service,
    String id,
    Map<String, dynamic> data, {
    bool validate = true,
  }) {
    return $create(
      service,
      {...data, 'id': id},
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

        final createdStr = item['created'] as String?;
        final updatedStr = item['updated'] as String?;

        final row = ServicesCompanion.insert(
          id: Value(id),
          data: item,
          service: service,
          created: Value((createdStr != null
                  ? DateTime.tryParse(createdStr)
                  : DateTime.now())
              ?.toIso8601String()),
          updated: Value((updatedStr != null
                  ? DateTime.tryParse(updatedStr)
                  : DateTime.now())
              ?.toIso8601String()),
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
      created: Value(DateTime.now().toIso8601String()),
      updated: Value(DateTime.now().toIso8601String()),
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

  /// Intelligently merges a list of items into the local database for a given service.
  ///
  /// This method is more efficient than `setLocal` for list updates because it
  /// only writes records that are new or have a more recent 'updated' timestamp
  /// than their local counterparts.
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
      final localRecords =
          await $query(service, filter: idFilter, fields: 'id, updated').get();
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
      if (localRecord == null) {
        // It's a new record, so add it.
        recordsToWrite.add(item);
      } else {
        // It's an existing record, check if it's updated.
        final networkUpdated =
            DateTime.tryParse(item['updated'] as String? ?? '');
        final localUpdated =
            DateTime.tryParse(localRecord['updated'] as String? ?? '');

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
        final createdStr = item['created'] as String?;
        final updatedStr = item['updated'] as String?;

        final row = ServicesCompanion.insert(
          id: Value(id),
          data: item,
          service: service,
          created: Value((createdStr != null
                  ? DateTime.tryParse(createdStr)
                  : DateTime.now())
              ?.toIso8601String()),
          updated: Value((updatedStr != null
                  ? DateTime.tryParse(updatedStr)
                  : DateTime.now())
              ?.toIso8601String()),
        );
        b.insert(services, row, onConflict: DoUpdate((old) => row));
      }
    });
  }
}

// extension StringUtils on String {
//   List<String> multiSplit(Iterable<String> delimiters) => delimiters.isEmpty
//       ? [this]
//       : split(RegExp(delimiters.map(RegExp.escape).join('|')));
// }
