import 'dart:async';

import 'package:flutter/foundation.dart';
import "package:http/http.dart" as http;

import '../../../pocketbase_drift.dart';

mixin ServiceMixin<M extends Jsonable> on BaseCrudService<M> {
  String get service;

  @override
  $PocketBase get client;

  /// Resolves the effective request policy to use.
  ///
  /// If [methodPolicy] is explicitly provided, it takes precedence.
  /// Otherwise, the client's global [requestPolicy] is used.
  @protected
  RequestPolicy resolvePolicy(RequestPolicy? methodPolicy) =>
      methodPolicy ?? client.requestPolicy;

  /// Private helper to read MultipartFiles into a memory buffer.
  /// This is necessary because a stream can only be read once.
  Future<List<(String field, String? filename, Uint8List bytes)>> _bufferFiles(
    List<http.MultipartFile> files,
  ) async {
    if (files.isEmpty) return [];
    final buffered = <(String, String?, Uint8List)>[];
    for (final file in files) {
      final bytes = await file.finalize().toBytes();
      buffered.add((file.field, file.filename, bytes));
    }
    return buffered;
  }

  /// Private helper to modify the request body for cache-only file uploads.
  /// It adds the original filenames to the body, looking up the schema to
  /// determine if the field is single or multi-select.
  Future<void> _prepareCacheOnlyBody(
    Map<String, dynamic> body,
    List<(String field, String? filename, Uint8List bytes)> files,
  ) async {
    if (files.isEmpty) return;

    final collection =
        await client.db.$collections(service: service).getSingle();
    for (final file in files) {
      final fieldName = file.$1;
      final filename = file.$2;
      if (filename == null) continue;

      final schemaField =
          collection.fields.firstWhere((f) => f.name == fieldName);
      final isMultiSelect = schemaField.data['maxSelect'] != 1;

      final existing = body[fieldName];
      if (existing == null) {
        body[fieldName] = isMultiSelect ? [filename] : filename;
      } else if (existing is List) {
        if (!existing.contains(filename)) existing.add(filename);
      } else if (existing is String) {
        body[fieldName] = [existing, filename];
      }
    }
  }

  /// Private helper to save buffered file blobs to the local database.
  Future<void> _cacheFilesToDb(
    String recordId,
    Map<String, dynamic> recordData,
    List<(String field, String? filename, Uint8List bytes)> bufferedFiles,
  ) async {
    if (bufferedFiles.isEmpty) return;

    for (final fileData in bufferedFiles) {
      final fieldName = fileData.$1;
      final originalFilename = fileData.$2;
      final bytes = fileData.$3;
      final dynamic filenamesInRecord = recordData[fieldName];

      if (originalFilename == null) continue;

      if (filenamesInRecord is String) {
        await _cacheFileBlob(recordId, filenamesInRecord, bytes);
      } else if (filenamesInRecord is List && filenamesInRecord.isNotEmpty) {
        // Find the server-generated filename that corresponds to the original.
        final serverFilename = filenamesInRecord.firstWhere(
          (f) {
            if (f is! String) return false;
            if (f == originalFilename) return true; // Cache-only exact match
            final dotIndex = originalFilename.lastIndexOf('.');
            if (dotIndex == -1) return false;
            final nameWithoutExt = originalFilename.substring(0, dotIndex);
            return f.startsWith('${nameWithoutExt}_');
          },
          orElse: () => '',
        );

        if (serverFilename.isNotEmpty) {
          await _cacheFileBlob(recordId, serverFilename, bytes);
        }
      }
    }
  }

  @override
  Future<M> getOne(
    String id, {
    String? expand,
    String? fields,
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
    RequestPolicy? requestPolicy,
  }) async {
    final policy = resolvePolicy(requestPolicy);
    return policy.fetch<M>(
      label: service,
      client: client,
      remote: () => super.getOne(
        id,
        fields: fields,
        query: query,
        expand: expand,
        headers: headers,
      ),
      getLocal: () async {
        final result = await client.db
            .$query(
              service,
              expand: expand,
              fields: fields,
              filter: "id = '$id'",
            )
            .getSingleOrNull();
        if (result == null) {
          throw Exception(
            'Record ($id) not found in collection $service [cache]',
          );
        }
        return itemFactoryFunc(result);
      },
      setLocal: (value) async {
        await client.db.$create(service, value.toJson());
      },
    );
  }

  @override
  Future<List<M>> getFullList({
    int batch = 1000,
    String? expand,
    String? filter,
    String? sort,
    String? fields,
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
    RequestPolicy? requestPolicy,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final policy = resolvePolicy(requestPolicy);
    // For cache-only or network-only, use the standard flow
    if (policy == RequestPolicy.cacheOnly ||
        policy == RequestPolicy.networkOnly) {
      return _getFullListStandard(
        batch: batch,
        expand: expand,
        filter: filter,
        sort: sort,
        fields: fields,
        query: query,
        headers: headers,
        requestPolicy: policy,
        timeout: timeout,
      );
    }

    // For policies that involve the network, we want to sync deletions
    final result = <M>[];
    final allItems = <Map<String, dynamic>>[];

    Future<List<M>> request(int page) async {
      return getList(
        page: page,
        perPage: batch,
        filter: filter,
        sort: sort,
        fields: fields,
        expand: expand,
        query: query,
        headers: headers,
        requestPolicy: policy,
        timeout: timeout,
      ).then((list) {
        result.addAll(list.items);
        // Collect raw JSON for sync operation
        allItems.addAll(list.items.map((e) => e.toJson()).toList());

        client.logger.finer(
            'Fetched page for "$service": ${list.page}/${list.totalPages} (${list.items.length} items)');
        if (list.items.length < batch ||
            list.items.isEmpty ||
            list.page == list.totalPages) {
          // All pages fetched - now sync with deletion detection
          // syncLocal uses filter-aware deletion: only deletes local records
          // that match the same filter but weren't in the server response
          client.logger.fine(
              'Full list fetch complete for "$service", syncing with deletion detection (filter: ${filter ?? "none"})');
          client.db
              .syncLocal(service, allItems, filter: filter)
              .catchError((e) {
            client.logger.warning(
                'Error during syncLocal for "$service" after getFullList', e);
          });
          return result;
        }
        return request(page + 1);
      });
    }

    return request(1);
  }

  /// Standard getFullList implementation without deletion sync
  Future<List<M>> _getFullListStandard({
    required int batch,
    required String? expand,
    required String? filter,
    required String? sort,
    required String? fields,
    required Map<String, dynamic> query,
    required Map<String, String> headers,
    required RequestPolicy requestPolicy,
    required Duration timeout,
  }) {
    final result = <M>[];

    Future<List<M>> request(int page) async {
      return getList(
        page: page,
        perPage: batch,
        filter: filter,
        sort: sort,
        fields: fields,
        expand: expand,
        query: query,
        headers: headers,
        requestPolicy: requestPolicy,
        timeout: timeout,
      ).then((list) {
        result.addAll(list.items);
        client.logger.finer(
            'Fetched page for "$service": ${list.page}/${list.totalPages} (${list.items.length} items)');
        if (list.items.length < batch ||
            list.items.isEmpty ||
            list.page == list.totalPages) {
          return result;
        }
        return request(page + 1);
      });
    }

    return request(1);
  }

  @override
  Future<M> getFirstListItem(
    String filter, {
    String? expand,
    String? fields,
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
    RequestPolicy? requestPolicy,
  }) {
    final policy = resolvePolicy(requestPolicy);
    return policy.fetch<M>(
      label: service,
      client: client,
      remote: () {
        return getList(
          perPage: 1,
          filter: filter,
          expand: expand,
          fields: fields,
          query: query,
          headers: headers,
          requestPolicy: policy,
        ).then((result) {
          if (result.items.isEmpty) {
            throw ClientException(
              statusCode: 404,
              response: <String, dynamic>{
                "code": 404,
                "message": "The requested resource wasn't found.",
                "data": <String, dynamic>{},
              },
            );
          }
          return result.items.first;
        });
      },
      getLocal: () async {
        final item = await client.db
            .$query(
              service,
              expand: expand,
              fields: fields,
              filter: filter,
            )
            .getSingleOrNull();
        return itemFactoryFunc(item!);
      },
      setLocal: (value) async {
        await client.db.$create(
          service,
          value.toJson(),
        );
      },
    );
  }

  Future<M?> getFirstListItemOrNull(
    String filter, {
    String? expand,
    String? fields,
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
    RequestPolicy? requestPolicy,
  }) async {
    final policy = resolvePolicy(requestPolicy);
    try {
      return await getFirstListItem(
        filter,
        expand: expand,
        fields: fields,
        query: query,
        headers: headers,
        requestPolicy: policy,
      );
    } catch (e) {
      client.logger.fine(
          'getFirstListItemOrNull for "$service" with filter "$filter" returned null',
          e);
      return null;
    }
  }

  @override
  Future<ResultList<M>> getList({
    int page = 1,
    int perPage = 30,
    bool skipTotal = false,
    String? expand,
    String? filter,
    String? sort,
    String? fields,
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
    RequestPolicy? requestPolicy,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final policy = resolvePolicy(requestPolicy);
    return policy.fetch<ResultList<M>>(
      label: service,
      client: client,
      remote: () => super
          .getList(
            page: page,
            perPage: perPage,
            skipTotal: skipTotal,
            expand: expand,
            filter: filter,
            fields: fields,
            sort: sort,
            query: query,
            headers: headers,
          )
          .timeout(timeout),
      getLocal: () async {
        final limit = perPage;
        final offset = (page - 1) * perPage;
        final items = await client.db
            .$query(
              service,
              limit: limit,
              offset: offset,
              expand: expand,
              fields: fields,
              filter: filter,
              sort: sort,
            )
            .get();
        final results = items.map((e) => itemFactoryFunc(e)).toList();
        final count = await client.db.$count(service);
        final totalPages = (count / perPage).ceil();
        return ResultList(
          page: page,
          perPage: perPage,
          items: results,
          totalItems: count,
          totalPages: totalPages,
        );
      },
      setLocal: (value) async {
        // Use the more efficient merge operation for list fetches.
        await client.db
            .mergeLocal(service, value.items.map((e) => e.toJson()).toList());
      },
    );
  }

  Future<M?> getOneOrNull(
    String id, {
    String? expand,
    String? fields,
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
    RequestPolicy? requestPolicy,
  }) async {
    final policy = resolvePolicy(requestPolicy);
    try {
      final result = await getOne(
        id,
        requestPolicy: policy,
        expand: expand,
        fields: fields,
        query: query,
        headers: headers,
      );
      return result;
    } catch (e) {
      client.logger.fine('getOneOrNull for "$service/$id" returned null.', e);
    }
    return null;
  }

  Future<void> setLocal(
    List<M> items, {
    bool removeAll = true,
  }) async {
    await client.db.setLocal(
      service,
      items.map((e) => e.toJson()).toList(),
      removeAll: removeAll,
    );
  }

  Future<void> _cacheFileBlob(
      String recordId, String filename, Uint8List bytes) async {
    try {
      await client.db.setFile(recordId, filename, bytes);
      client.logger.fine('Cached file blob "$filename" for record "$recordId"');
    } catch (e) {
      client.logger.warning(
          'Error caching file blob "$filename" for record "$recordId"', e);
    }
  }

  @override
  Future<M> create({
    RequestPolicy? requestPolicy,
    Map<String, dynamic> body = const {},
    Map<String, dynamic> query = const {},
    List<http.MultipartFile> files = const [],
    Map<String, String> headers = const {},
    String? expand,
    String? fields,
  }) async {
    final policy = resolvePolicy(requestPolicy);
    return switch (policy) {
      RequestPolicy.cacheOnly =>
        _createCacheOnly(body, query, files, headers, expand, fields),
      RequestPolicy.networkOnly =>
        _createNetworkOnly(body, query, files, headers, expand, fields),
      RequestPolicy.cacheFirst =>
        _createCacheFirst(body, query, files, headers, expand, fields),
      RequestPolicy.networkFirst =>
        _createNetworkFirst(body, query, files, headers, expand, fields),
      RequestPolicy.cacheAndNetwork =>
        _createCacheAndNetwork(body, query, files, headers, expand, fields),
    };
  }

  Future<M> _createCacheOnly(
    Map<String, dynamic> body,
    Map<String, dynamic> query,
    List<http.MultipartFile> files,
    Map<String, String> headers,
    String? expand,
    String? fields,
  ) async {
    final bufferedFiles = await _bufferFiles(files);
    Map<String, dynamic> recordDataForCache = Map.from(body);
    await _prepareCacheOnlyBody(recordDataForCache, bufferedFiles);

    final localRecordData = await client.db.$create(
      service,
      {
        ...recordDataForCache,
        'deleted': false,
        'synced': false,
        'isNew': true, // Explicitly mark as new
        'noSync': true, // Mark as local-only
      },
    );

    final recordIdForFiles = localRecordData['id'] as String?;
    if (recordIdForFiles != null) {
      await _cacheFilesToDb(recordIdForFiles, localRecordData, bufferedFiles);
    }
    return itemFactoryFunc(localRecordData);
  }

  Future<M> _createNetworkOnly(
    Map<String, dynamic> body,
    Map<String, dynamic> query,
    List<http.MultipartFile> files,
    Map<String, String> headers,
    String? expand,
    String? fields,
  ) async {
    if (!client.connectivity.shouldAttemptNetwork) {
      throw Exception(
          'Device is offline and RequestPolicy.networkOnly was requested for create in $service.');
    }

    final bufferedFiles = await _bufferFiles(files);
    return await super.create(
      body: body,
      query: query,
      headers: headers,
      expand: expand,
      fields: fields,
      files: bufferedFiles
          .map((d) => http.MultipartFile.fromBytes(d.$1, d.$3, filename: d.$2))
          .toList(),
    );
  }

  Future<M> _createCacheFirst(
    Map<String, dynamic> body,
    Map<String, dynamic> query,
    List<http.MultipartFile> files,
    Map<String, String> headers,
    String? expand,
    String? fields,
  ) async {
    final bufferedFiles = await _bufferFiles(files);
    Map<String, dynamic> recordDataForCache = Map.from(body);

    if (bufferedFiles.isNotEmpty) {
      await _prepareCacheOnlyBody(recordDataForCache, bufferedFiles);
    }

    // Write to cache first
    final localRecordData = await client.db.$create(
      service,
      {
        ...recordDataForCache,
        'deleted': false,
        'synced': false,
        'isNew': true,
        'noSync': false, // Will try to sync
      },
    );

    final recordIdForFiles = localRecordData['id'] as String?;
    if (recordIdForFiles != null) {
      await _cacheFilesToDb(recordIdForFiles, localRecordData, bufferedFiles);
    }

    final result = itemFactoryFunc(localRecordData);

    // Try server in background
    if (client.connectivity.shouldAttemptNetwork) {
      _tryCreateOnServer(body, query, bufferedFiles, headers, expand, fields,
              localRecordData['id'] as String)
          .catchError((e) {
        client.logger.warning(
            'Background create for $service failed, will retry later.', e);
      });
    }

    return result;
  }

  Future<void> _tryCreateOnServer(
    Map<String, dynamic> body,
    Map<String, dynamic> query,
    List<(String, String?, Uint8List)> bufferedFiles,
    Map<String, String> headers,
    String? expand,
    String? fields,
    String localId,
  ) async {
    try {
      final serverRecord = await super.create(
        body: {...body, 'id': localId},
        query: query,
        headers: headers,
        expand: expand,
        fields: fields,
        files: bufferedFiles
            .map(
                (d) => http.MultipartFile.fromBytes(d.$1, d.$3, filename: d.$2))
            .toList(),
      );

      // Check if server used our ID or generated a new one
      final serverRecordData = serverRecord.toJson();
      final serverId = serverRecordData['id'] as String?;

      if (serverId != null && serverId != localId) {
        // Server rejected our ID - delete the old local record and create new one
        client.logger.warning('Server did not use provided ID for $service. '
            'Sent: $localId, Received: $serverId. Updating local record.');
        await client.db.$delete(service, localId);
        await client.db.$create(
          service,
          {
            ...serverRecordData,
            'synced': true,
            'isNew': false,
          },
        );
      } else {
        // Server used our ID - just update the local record
        await client.db.$update(
          service,
          localId,
          {
            ...serverRecordData,
            'synced': true,
            'isNew': false,
          },
        );
      }

      // Cache the files with their server-generated names
      if (bufferedFiles.isNotEmpty) {
        final finalId = serverId ?? localId;
        await _cacheFilesToDb(finalId, serverRecordData, bufferedFiles);
      }

      client.logger
          .fine('Background create for $service/$localId synced successfully.');
    } catch (e) {
      client.logger
          .warning('Background create for $service/$localId failed.', e);
      rethrow;
    }
  }

  Future<M> _createNetworkFirst(
    Map<String, dynamic> body,
    Map<String, dynamic> query,
    List<http.MultipartFile> files,
    Map<String, String> headers,
    String? expand,
    String? fields,
  ) async {
    if (!client.connectivity.shouldAttemptNetwork) {
      throw Exception(
          'Device is offline and RequestPolicy.networkFirst was requested for create in $service.');
    }

    final bufferedFiles = await _bufferFiles(files);
    M result;

    // Try network first (strict - no fallback)
    try {
      result = await super.create(
        body: body,
        query: query,
        headers: headers,
        expand: expand,
        fields: fields,
        files: bufferedFiles
            .map(
                (d) => http.MultipartFile.fromBytes(d.$1, d.$3, filename: d.$2))
            .toList(),
      );
    } on ClientException catch (e) {
      if (e.statusCode == 400 && body['id'] != null) {
        final id = body['id'] as String;
        final updateBody = Map<String, dynamic>.from(body)..remove('id');
        result = await super.update(
          id,
          body: updateBody,
          query: query,
          headers: headers,
          expand: expand,
          fields: fields,
          files: bufferedFiles
              .map((d) =>
                  http.MultipartFile.fromBytes(d.$1, d.$3, filename: d.$2))
              .toList(),
        );
      } else {
        rethrow;
      }
    }

    // Update cache after successful network operation
    final recordDataForCache = result.toJson();
    await client.db.$create(
      service,
      {
        ...recordDataForCache,
        'deleted': false,
        'synced': true,
      },
    );

    final recordIdForFiles = recordDataForCache['id'] as String?;
    if (recordIdForFiles != null) {
      await _cacheFilesToDb(
          recordIdForFiles, recordDataForCache, bufferedFiles);
    }

    return result;
  }

  Future<M> _createCacheAndNetwork(
    Map<String, dynamic> body,
    Map<String, dynamic> query,
    List<http.MultipartFile> files,
    Map<String, String> headers,
    String? expand,
    String? fields,
  ) async {
    final bufferedFiles = await _bufferFiles(files);
    Map<String, dynamic> recordDataForCache = Map.from(body);
    M? result;
    bool savedToNetwork = false;

    // Generate a local PocketBase-compatible ID upfront.
    // This ID will be used for both local cache and server creation.
    final localId = body['id'] as String? ?? newId();
    recordDataForCache['id'] = localId;

    // Prepare filenames for cache-only storage upfront.
    // This ensures file field names are saved even when offline.
    if (bufferedFiles.isNotEmpty) {
      await _prepareCacheOnlyBody(recordDataForCache, bufferedFiles);
    }

    // Try network if connected
    if (client.connectivity.shouldAttemptNetwork) {
      try {
        // Include our local ID so the server uses it
        result = await super.create(
          body: {...body, 'id': localId},
          query: query,
          headers: headers,
          expand: expand,
          fields: fields,
          files: bufferedFiles
              .map((d) =>
                  http.MultipartFile.fromBytes(d.$1, d.$3, filename: d.$2))
              .toList(),
        );
        savedToNetwork = true;
        recordDataForCache = result.toJson();
      } on ClientException catch (e) {
        // If creation fails with 400 and we have an ID, try update instead
        // (the record might already exist from a previous partial sync)
        if (e.statusCode == 400) {
          final updateBody = Map<String, dynamic>.from(body)..remove('id');
          try {
            result = await super.update(
              localId,
              body: updateBody,
              query: query,
              headers: headers,
              expand: expand,
              fields: fields,
              files: bufferedFiles
                  .map((d) =>
                      http.MultipartFile.fromBytes(d.$1, d.$3, filename: d.$2))
                  .toList(),
            );
            savedToNetwork = true;
            recordDataForCache = result.toJson();
          } catch (updateE) {
            client.logger.warning(
                'Failed to create (then update) record $localId in $service: $e, then $updateE');
          }
        } else {
          client.logger
              .warning('Failed to create record $localId in $service: $e');
        }
      } catch (e) {
        client.logger
            .warning('Failed to create record $localId in $service: $e');
      }
    }

    // If the server returned a different ID than what we sent (indicating our
    // localId was rejected/overwritten), use the server's ID instead.
    final serverId = recordDataForCache['id'] as String?;
    final finalId = (savedToNetwork && serverId != null && serverId != localId)
        ? serverId
        : localId;

    if (savedToNetwork && serverId != null && serverId != localId) {
      client.logger.warning('Server did not use provided ID for $service. '
          'Sent: $localId, Received: $serverId. Using server ID.');
    }

    // Save to cache with the determined ID
    final localRecordData = await client.db.$create(
      service,
      {
        ...recordDataForCache,
        'id': finalId,
        'deleted': false,
        'synced': savedToNetwork,
        'isNew': !savedToNetwork,
        'noSync': false,
      },
    );

    if (bufferedFiles.isNotEmpty) {
      await _cacheFilesToDb(finalId, localRecordData, bufferedFiles);
    }
    result = itemFactoryFunc(localRecordData);

    return result;
  }

  @override
  Future<M> update(
    String id, {
    RequestPolicy? requestPolicy,
    Map<String, dynamic> body = const {},
    Map<String, dynamic> query = const {},
    List<http.MultipartFile> files = const [],
    Map<String, String> headers = const {},
    String? expand,
    String? fields,
  }) async {
    // Validate that ID is not empty - calling update with an empty ID
    // would cause unpredictable behavior (server errors or creating new records).
    if (id.isEmpty) {
      throw ArgumentError.value(
        id,
        'id',
        'Cannot update a record with an empty ID in collection "$service". '
            'Ensure you have a valid record ID before calling update().',
      );
    }

    final policy = resolvePolicy(requestPolicy);
    return switch (policy) {
      RequestPolicy.cacheOnly =>
        _updateCacheOnly(id, body, query, files, headers, expand, fields),
      RequestPolicy.networkOnly =>
        _updateNetworkOnly(id, body, query, files, headers, expand, fields),
      RequestPolicy.cacheFirst =>
        _updateCacheFirst(id, body, query, files, headers, expand, fields),
      RequestPolicy.networkFirst =>
        _updateNetworkFirst(id, body, query, files, headers, expand, fields),
      RequestPolicy.cacheAndNetwork =>
        _updateCacheAndNetwork(id, body, query, files, headers, expand, fields),
    };
  }

  Future<M> _updateCacheOnly(
    String id,
    Map<String, dynamic> body,
    Map<String, dynamic> query,
    List<http.MultipartFile> files,
    Map<String, String> headers,
    String? expand,
    String? fields,
  ) async {
    final bufferedFiles = await _bufferFiles(files);
    Map<String, dynamic> recordDataForCache = Map.from(body);
    await _prepareCacheOnlyBody(recordDataForCache, bufferedFiles);

    final localRecordData = await client.db.$update(
      service,
      id,
      {
        'deleted': false,
        ...recordDataForCache,
        'synced': false,
        'isNew': false,
        'noSync': true,
      },
    );
    await _cacheFilesToDb(id, localRecordData, bufferedFiles);
    return itemFactoryFunc(localRecordData);
  }

  Future<M> _updateNetworkOnly(
    String id,
    Map<String, dynamic> body,
    Map<String, dynamic> query,
    List<http.MultipartFile> files,
    Map<String, String> headers,
    String? expand,
    String? fields,
  ) async {
    if (!client.connectivity.shouldAttemptNetwork) {
      throw Exception(
          'Device is offline and RequestPolicy.networkOnly was requested for update in $service.');
    }

    final bufferedFiles = await _bufferFiles(files);
    return await super.update(
      id,
      body: body,
      query: query,
      headers: headers,
      expand: expand,
      fields: fields,
      files: bufferedFiles
          .map((d) => http.MultipartFile.fromBytes(d.$1, d.$3, filename: d.$2))
          .toList(),
    );
  }

  Future<M> _updateCacheFirst(
    String id,
    Map<String, dynamic> body,
    Map<String, dynamic> query,
    List<http.MultipartFile> files,
    Map<String, String> headers,
    String? expand,
    String? fields,
  ) async {
    final bufferedFiles = await _bufferFiles(files);
    Map<String, dynamic> recordDataForCache = Map.from(body);

    if (bufferedFiles.isNotEmpty) {
      await _prepareCacheOnlyBody(recordDataForCache, bufferedFiles);
    }

    // Write to cache first
    final localRecordData = await client.db.$update(
      service,
      id,
      {
        'deleted': false,
        ...recordDataForCache,
        'synced': false,
        'isNew': false,
        'noSync': false, // Will try to sync
      },
    );
    await _cacheFilesToDb(id, localRecordData, bufferedFiles);

    final result = itemFactoryFunc(localRecordData);

    // Try server in background
    if (client.connectivity.shouldAttemptNetwork) {
      _tryUpdateOnServer(
              id, body, query, bufferedFiles, headers, expand, fields)
          .catchError((e) {
        client.logger.warning(
            'Background update for $service/$id failed, will retry later.', e);
      });
    }

    return result;
  }

  Future<void> _tryUpdateOnServer(
    String id,
    Map<String, dynamic> body,
    Map<String, dynamic> query,
    List<(String, String?, Uint8List)> bufferedFiles,
    Map<String, String> headers,
    String? expand,
    String? fields,
  ) async {
    try {
      final serverRecord = await super.update(
        id,
        body: body,
        query: query,
        headers: headers,
        expand: expand,
        fields: fields,
        files: bufferedFiles
            .map(
                (d) => http.MultipartFile.fromBytes(d.$1, d.$3, filename: d.$2))
            .toList(),
      );

      // Update local record to mark as synced and update with server data (including renamed files)
      final serverRecordData = serverRecord.toJson();
      await client.db.$update(
        service,
        id,
        {
          ...serverRecordData,
          'synced': true,
          'isNew': false,
        },
      );

      // Cache the files with their server-generated names
      if (bufferedFiles.isNotEmpty) {
        await _cacheFilesToDb(id, serverRecordData, bufferedFiles);
      }

      client.logger
          .fine('Background update for $service/$id synced successfully.');
    } catch (e) {
      client.logger.warning('Background update for $service/$id failed.', e);
      rethrow;
    }
  }

  Future<M> _updateNetworkFirst(
    String id,
    Map<String, dynamic> body,
    Map<String, dynamic> query,
    List<http.MultipartFile> files,
    Map<String, String> headers,
    String? expand,
    String? fields,
  ) async {
    if (!client.connectivity.shouldAttemptNetwork) {
      throw Exception(
          'Device is offline and RequestPolicy.networkFirst was requested for update in $service.');
    }

    final bufferedFiles = await _bufferFiles(files);
    M result;

    // Try network first (strict - no fallback)
    try {
      result = await super.update(
        id,
        body: body,
        query: query,
        headers: headers,
        expand: expand,
        fields: fields,
        files: bufferedFiles
            .map(
                (d) => http.MultipartFile.fromBytes(d.$1, d.$3, filename: d.$2))
            .toList(),
      );
    } on ClientException catch (e) {
      if (e.statusCode == 404 || e.statusCode == 400) {
        result = await super.create(
          body: {...body, 'id': id},
          query: query,
          headers: headers,
          expand: expand,
          fields: fields,
          files: bufferedFiles
              .map((d) =>
                  http.MultipartFile.fromBytes(d.$1, d.$3, filename: d.$2))
              .toList(),
        );
      } else {
        rethrow;
      }
    }

    // Update cache after successful network operation
    final recordDataForCache = result.toJson();
    await client.db.$update(
      service,
      id,
      {
        'deleted': false,
        ...recordDataForCache,
        'synced': true,
        'isNew': false,
      },
    );
    await _cacheFilesToDb(id, recordDataForCache, bufferedFiles);

    return result;
  }

  Future<M> _updateCacheAndNetwork(
    String id,
    Map<String, dynamic> body,
    Map<String, dynamic> query,
    List<http.MultipartFile> files,
    Map<String, String> headers,
    String? expand,
    String? fields,
  ) async {
    final bufferedFiles = await _bufferFiles(files);
    Map<String, dynamic> recordDataForCache = Map.from(body);
    M? result;
    bool savedToNetwork = false;

    // Prepare filenames for cache-only storage upfront.
    // This ensures file field names are saved even when offline.
    if (bufferedFiles.isNotEmpty) {
      await _prepareCacheOnlyBody(recordDataForCache, bufferedFiles);
    }

    // Try network if connected
    if (client.connectivity.shouldAttemptNetwork) {
      try {
        result = await super.update(
          id,
          body: body,
          query: query,
          headers: headers,
          expand: expand,
          fields: fields,
          files: bufferedFiles
              .map((d) =>
                  http.MultipartFile.fromBytes(d.$1, d.$3, filename: d.$2))
              .toList(),
        );
        savedToNetwork = true;
        recordDataForCache = result.toJson();
      } on ClientException catch (e) {
        if (e.statusCode == 404 || e.statusCode == 400) {
          try {
            result = await super.create(
              body: {...body, 'id': id},
              query: query,
              headers: headers,
              expand: expand,
              fields: fields,
              files: bufferedFiles
                  .map((d) =>
                      http.MultipartFile.fromBytes(d.$1, d.$3, filename: d.$2))
                  .toList(),
            );
            savedToNetwork = true;
            recordDataForCache = result.toJson();
          } catch (createE) {
            client.logger.warning(
                'Failed to update (then create) record $id in $service: $e, then $createE');
          }
        } else {
          client.logger.warning('Failed to update record $id in $service: $e');
        }
      } catch (e) {
        client.logger.warning('Failed to update record $id in $service: $e');
      }
    }

    // Fallback to cache with pending sync
    final localRecordData = await client.db.$update(
      service,
      id,
      {
        'deleted': false,
        ...recordDataForCache,
        'synced': savedToNetwork,
        'isNew': false,
        'noSync': false,
      },
    );
    await _cacheFilesToDb(id, localRecordData, bufferedFiles);
    result = itemFactoryFunc(localRecordData);

    return result;
  }

  @override
  Future<void> delete(
    String id, {
    RequestPolicy? requestPolicy,
    Map<String, dynamic> body = const {},
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
  }) async {
    final policy = resolvePolicy(requestPolicy);
    return switch (policy) {
      RequestPolicy.cacheOnly => _deleteCacheOnly(id, body, query, headers),
      RequestPolicy.networkOnly => _deleteNetworkOnly(id, body, query, headers),
      RequestPolicy.cacheFirst => _deleteCacheFirst(id, body, query, headers),
      RequestPolicy.networkFirst =>
        _deleteNetworkFirst(id, body, query, headers),
      RequestPolicy.cacheAndNetwork =>
        _deleteCacheAndNetwork(id, body, query, headers),
    };
  }

  Future<void> _deleteCacheOnly(
    String id,
    Map<String, dynamic> body,
    Map<String, dynamic> query,
    Map<String, String> headers,
  ) async {
    // For cacheOnly, mark as deleted instead of actually deleting
    // This allows the record to be tracked but not synced to server
    await _updateCacheOnly(
      id,
      {
        ...body,
        'deleted': true,
      },
      query,
      [],
      headers,
      null,
      null,
    );
  }

  Future<void> _deleteNetworkOnly(
    String id,
    Map<String, dynamic> body,
    Map<String, dynamic> query,
    Map<String, String> headers,
  ) async {
    if (!client.connectivity.shouldAttemptNetwork) {
      throw Exception(
          'Device is offline and RequestPolicy.networkOnly was requested for delete in $service.');
    }

    await super.delete(
      id,
      body: body,
      query: query,
      headers: headers,
    );
  }

  Future<void> _deleteCacheFirst(
    String id,
    Map<String, dynamic> body,
    Map<String, dynamic> query,
    Map<String, String> headers,
  ) async {
    // Mark as a tombstone first so the deletion survives until the server
    // confirms it. A hard local delete would lose the pending change when
    // the background server delete fails (e.g. offline).
    final existing = await client.db
        .$query(service, filter: "id = '$id'", includeDeleted: true)
        .getSingleOrNull();
    if (existing != null) {
      await client.db.$update(
        service,
        id,
        {
          ...body,
          'deleted': true,
          'synced': false,
          'isNew': existing['isNew'] == true,
          'noSync': false,
        },
      );
    }

    // Try server in background; on success drop the local row entirely.
    if (client.connectivity.shouldAttemptNetwork) {
      super
          .delete(id, body: body, query: query, headers: headers)
          .then((_) => client.db.$delete(service, id))
          .catchError((e) {
        client.logger.warning(
            'Background delete for $service/$id failed, will retry when connectivity returns.',
            e);
      });
    }
  }

  Future<void> _deleteNetworkFirst(
    String id,
    Map<String, dynamic> body,
    Map<String, dynamic> query,
    Map<String, String> headers,
  ) async {
    if (!client.connectivity.shouldAttemptNetwork) {
      throw Exception(
          'Device is offline and RequestPolicy.networkFirst was requested for delete in $service.');
    }

    // Try network first (strict - no fallback)
    await super.delete(
      id,
      body: body,
      query: query,
      headers: headers,
    );

    // Delete from cache after successful network operation
    await client.db.$delete(service, id);
  }

  Future<void> _deleteCacheAndNetwork(
    String id,
    Map<String, dynamic> body,
    Map<String, dynamic> query,
    Map<String, String> headers,
  ) async {
    bool saved = false;

    // Try network if connected
    if (client.connectivity.shouldAttemptNetwork) {
      try {
        await super.delete(
          id,
          body: body,
          query: query,
          headers: headers,
        );
        saved = true;
      } catch (e) {
        client.logger.warning('Failed to delete record $id in $service: $e');
      }
    }

    // Fallback to marking as deleted
    if (saved) {
      await client.db.$delete(service, id);
    } else {
      // Mark as a tombstone so the deletion survives until the server can
      // confirm it. isNew is preserved so retryLocal can purge locally
      // created records without a doomed server round-trip.
      final existing = await client.db
          .$query(service, filter: "id = '$id'", includeDeleted: true)
          .getSingleOrNull();
      if (existing != null) {
        await client.db.$update(
          service,
          id,
          {
            ...body,
            'deleted': true,
            'synced': false,
            'isNew': existing['isNew'] == true,
            'noSync': false,
          },
        );
      } else {
        client.logger.warning(
            'Cannot delete $service/$id while offline: record is not cached locally.');
      }
    }
  }
}

class RetryProgressEvent {
  final int total;
  final int current;

  const RetryProgressEvent({
    required this.total,
    required this.current,
  });

  double get progress => current / total;
}

/// Defines how data should be fetched and synchronized between local cache and remote server.
///
/// For read operations (GET):
/// - [cacheOnly]: Only read from cache, never contact server
/// - [networkOnly]: Only read from server, never use cache
/// - [cacheFirst]: Return cache immediately, fetch network in background to update cache
/// - [networkFirst]: Try network first, fallback to cache if network fails
/// - [cacheAndNetwork]: Try network, fallback to cache on failure (legacy behavior)
///
/// For write operations (CREATE/UPDATE/DELETE):
/// - [cacheOnly]: Write to cache only with noSync flag (never syncs to server)
/// - [networkOnly]: Write to server only, throw error if fails
/// - [cacheFirst]: Write to cache first, then try server in background
/// - [networkFirst]: Write to server first, then update cache (strict, no fallback)
/// - [cacheAndNetwork]: Try server, fallback to cache with pending sync on failure (offline-first)
enum RequestPolicy {
  cacheOnly,
  networkOnly,
  cacheFirst,
  networkFirst,
  cacheAndNetwork,
}

extension RequestPolicyUtils on RequestPolicy {
  /// Returns true if the policy performs a synchronous network operation
  /// that blocks and returns network data immediately.
  ///
  /// Note: `cacheFirst` is not included even though it syncs to network in background,
  /// because it returns cache data immediately without waiting for network.
  bool get isNetwork =>
      this == RequestPolicy.networkOnly ||
      this == RequestPolicy.networkFirst ||
      this == RequestPolicy.cacheAndNetwork;

  /// Returns true if the policy reads from or writes to cache.
  bool get isCache =>
      this == RequestPolicy.cacheOnly ||
      this == RequestPolicy.cacheFirst ||
      this == RequestPolicy.networkFirst ||
      this == RequestPolicy.cacheAndNetwork;

  /// Fetch data for read operations (GET requests).
  ///
  /// This method handles the different policies for reading data:
  /// - [cacheOnly]: Only reads from cache
  /// - [networkOnly]: Only reads from network
  /// - [cacheFirst]: Returns cache immediately, updates in background
  /// - [networkFirst]: Tries network first, falls back to cache
  /// - [cacheAndNetwork]: Tries network, falls back to cache (same as networkFirst for reads)
  Future<T> fetch<T>({
    required String label,
    required $PocketBase client,
    required Future<T> Function() remote,
    required Future<T> Function() getLocal,
    required Future<void> Function(T) setLocal,
  }) async {
    client.logger.finer('Fetching "$label" with policy "$name"');

    return switch (this) {
      RequestPolicy.cacheOnly => _fetchCacheOnly(label, client, getLocal),
      RequestPolicy.networkOnly => _fetchNetworkOnly(label, client, remote),
      RequestPolicy.cacheFirst =>
        _fetchCacheFirst(label, client, remote, getLocal, setLocal),
      RequestPolicy.networkFirst =>
        _fetchNetworkFirst(label, client, remote, getLocal, setLocal),
      RequestPolicy.cacheAndNetwork =>
        _fetchNetworkFirst(label, client, remote, getLocal, setLocal),
    };
  }

  Future<T> _fetchCacheOnly<T>(
    String label,
    $PocketBase client,
    Future<T> Function() getLocal,
  ) async {
    try {
      client.logger.finer('Fetching "$label" from cache only...');
      return await getLocal();
    } catch (e) {
      client.logger.warning('Cache fetch for "$label" failed.', e);
      rethrow;
    }
  }

  Future<T> _fetchNetworkOnly<T>(
    String label,
    $PocketBase client,
    Future<T> Function() remote,
  ) async {
    if (!client.connectivity.shouldAttemptNetwork) {
      throw Exception(
          'Device is offline and RequestPolicy.networkOnly was requested for "$label".');
    }

    try {
      client.logger.finer('Fetching "$label" from network only...');
      final result = await remote();
      client.connectivity.reportNetworkSuccess();
      return result;
    } catch (e) {
      client.connectivity.reportNetworkFailure();
      client.logger.warning('Network fetch for "$label" failed.', e);
      rethrow;
    }
  }

  Future<T> _fetchCacheFirst<T>(
    String label,
    $PocketBase client,
    Future<T> Function() remote,
    Future<T> Function() getLocal,
    Future<void> Function(T) setLocal,
  ) async {
    T? result;

    // First, try to get from cache
    try {
      client.logger.finer('Fetching "$label" from cache first...');
      result = await getLocal();
    } catch (e) {
      client.logger
          .fine('Cache fetch for "$label" failed, will try network.', e);
    }

    // Then fetch from network in background to update cache
    if (client.connectivity.shouldAttemptNetwork) {
      // Fire and forget - don't await
      remote().then((networkData) async {
        client.connectivity.reportNetworkSuccess();
        try {
          await setLocal(networkData);
          client.logger.finer('Background update for "$label" completed.');
        } catch (e) {
          client.logger
              .warning('Failed to update cache for "$label" in background.', e);
        }
      }).catchError((e) {
        client.connectivity.reportNetworkFailure();
        client.logger.fine('Background network fetch for "$label" failed.', e);
      });
    }

    if (result == null) {
      throw Exception(
          'Cache miss for "$label" with cacheFirst policy and no network available.');
    }

    return result;
  }

  Future<T> _fetchNetworkFirst<T>(
    String label,
    $PocketBase client,
    Future<T> Function() remote,
    Future<T> Function() getLocal,
    Future<void> Function(T) setLocal,
  ) async {
    Object? error;

    // Try network first if platform reports a network interface is available
    if (client.connectivity.shouldAttemptNetwork) {
      try {
        client.logger.finer('Fetching "$label" from network first...');
        final result = await remote();
        client.connectivity.reportNetworkSuccess();
        // Update cache with network data
        try {
          await setLocal(result);
        } catch (e) {
          client.logger.warning(
              'Failed to update cache for "$label" after network fetch.', e);
        }
        return result;
      } catch (e) {
        client.connectivity.reportNetworkFailure();
        error = e;
        client.logger.warning('Network fetch for "$label" failed.', e);
      }
    } else {
      client.logger
          .info('No network interface. Skipping network request for "$label".');
    }

    // Fallback to cache
    try {
      client.logger.finer('Falling back to cache for "$label"...');
      final result = await getLocal();
      return result;
    } catch (e) {
      client.logger.warning('Cache fallback for "$label" failed.', e);
      throw Exception(
          'Failed to fetch "$label": Network error: $error, Cache error: $e');
    }
  }
}
