import 'dart:async';

import 'package:flutter/foundation.dart';
import "package:http/http.dart" as http;

import '../../../pocketbase_drift.dart';

mixin ServiceMixin<M extends Jsonable> on BaseCrudService<M> {
  String get service;

  @override
  $PocketBase get client;

  @override
  Future<M> getOne(
    String id, {
    String? expand,
    String? fields,
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
    RequestPolicy requestPolicy = RequestPolicy.cacheAndNetwork,
  }) async {
    return requestPolicy.fetch<M>(
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
    int batch = 200,
    String? expand,
    String? filter,
    String? sort,
    String? fields,
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
    RequestPolicy requestPolicy = RequestPolicy.cacheAndNetwork,
    Duration timeout = const Duration(seconds: 30),
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
    RequestPolicy requestPolicy = RequestPolicy.cacheAndNetwork,
  }) {
    return requestPolicy.fetch<M>(
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
          requestPolicy: requestPolicy,
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
    RequestPolicy requestPolicy = RequestPolicy.cacheAndNetwork,
  }) async {
    try {
      return getFirstListItem(
        filter,
        expand: expand,
        fields: fields,
        query: query,
        headers: headers,
        requestPolicy: requestPolicy,
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
    RequestPolicy requestPolicy = RequestPolicy.cacheAndNetwork,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    return requestPolicy.fetch<ResultList<M>>(
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
    RequestPolicy requestPolicy = RequestPolicy.cacheAndNetwork,
  }) async {
    try {
      final result = await getOne(
        id,
        requestPolicy: requestPolicy,
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
    RequestPolicy requestPolicy = RequestPolicy.cacheAndNetwork,
    Map<String, dynamic> body = const {},
    Map<String, dynamic> query = const {},
    List<http.MultipartFile> files = const [],
    Map<String, String> headers = const {},
    String? expand,
    String? fields,
  }) async {
    // Buffer the raw file data immediately. A MultipartFile can only be read once.
    final List<(String field, String? filename, Uint8List bytes)>
        bufferedFilesData = [];
    if (files.isNotEmpty) {
      for (final file in files) {
        final bytes = await file.finalize().toBytes();
        bufferedFilesData.add((file.field, file.filename, bytes));
      }
    }

    M? result;
    bool savedToNetwork = false;
    Map<String, dynamic> recordDataForCache =
        Map.from(body); // Start with body for cache

    // For cache-only, we need to manually add filenames to the record data
    if (requestPolicy == RequestPolicy.cacheOnly) {
      for (final file in files) {
        final fieldName = file.field;
        final filename = file.filename;
        if (filename == null) continue;

        // We MUST look up the schema to know if the field is multi-select.
        final collection =
            await client.db.$collections(service: service).getSingle();
        final schemaField =
            collection.fields.firstWhere((f) => f.name == fieldName);
        final isMultiSelect = schemaField.data['maxSelect'] != 1;

        final existing = recordDataForCache[fieldName];
        if (existing == null) {
          recordDataForCache[fieldName] = isMultiSelect ? [filename] : filename;
        } else if (existing is List) {
          existing.add(filename);
        } else {
          // It was a string, but now we have another file. This case shouldn't
          // happen if the schema is respected, but as a fallback, convert to list.
          recordDataForCache[fieldName] = [existing, filename];
        }
      }
    }

    if (requestPolicy.isNetwork && client.connectivity.isConnected) {
      try {
        result = await super.create(
          body: body,
          query: query,
          headers: headers,
          expand: expand,
          fields: fields,
          // Create fresh MultipartFile instances for the network call
          files: bufferedFilesData.map((d) {
            return http.MultipartFile.fromBytes(d.$1, d.$3, filename: d.$2);
          }).toList(),
        );
        savedToNetwork = true;
        recordDataForCache =
            result.toJson(); // Use network result for cache if successful
      } on ClientException catch (e) {
        if (e.statusCode == 400 && body['id'] != null) {
          // If create failed with 400 (e.g. record exists), try to update
          final id = body['id'] as String;
          final updateBody = Map<String, dynamic>.from(body)..remove('id');
          try {
            result = await super.update(
              id,
              body: updateBody,
              query: query,
              files: files,
              headers: headers,
              expand: expand,
              fields: fields,
            );
            savedToNetwork = true;
            recordDataForCache = result.toJson();
          } catch (updateE) {
            final msg =
                'Failed to create (then update) record $body in $service: $e, then $updateE';
            if (requestPolicy == RequestPolicy.networkOnly) {
              throw Exception(msg);
            }
            debugPrint(msg);
          }
        } else {
          final msg = 'Failed to create record $body in $service: $e';
          if (requestPolicy == RequestPolicy.networkOnly) throw Exception(msg);
          debugPrint(msg);
        }
      } catch (e) {
        final msg = 'Failed to create record $body in $service: $e';
        if (requestPolicy == RequestPolicy.networkOnly) throw Exception(msg);
        debugPrint(msg);
      }
    }

    if (requestPolicy.isCache) {
      final shouldNoSync = requestPolicy == RequestPolicy.cacheOnly;
      final localRecordData = await client.db.$create(
        service,
        {
          ...recordDataForCache,
          'deleted': false,
          'synced': savedToNetwork,
          'isNew': !savedToNetwork ? true : null,
          'noSync': shouldNoSync,
        },
      );

      final recordIdForFiles = localRecordData['id'] as String?;
      if (recordIdForFiles != null && bufferedFilesData.isNotEmpty) {
        for (final fileData in bufferedFilesData) {
          // Get the filename(s) from the record data we just prepared.
          // It will be the server-generated one for network, or original for cache-only.
          final dynamic filenamesInRecord = recordDataForCache[fileData.$1];
          final bytes = fileData.$3; // Use bytes directly from buffer

          if (filenamesInRecord is String) {
            // Handle single file field
            await _cacheFileBlob(recordIdForFiles, filenamesInRecord, bytes);
          } else if (filenamesInRecord is List &&
              filenamesInRecord.isNotEmpty) {
            // Handle multi-file field by finding the matching original filename
            final originalFilename = fileData.$2;
            if (originalFilename == null) continue;

            final serverFilename = filenamesInRecord.firstWhere((f) {
              if (f is! String) return false;
              // Exact match (cacheOnly case)
              if (f == originalFilename) return true;

              // Check for server-renamed pattern
              final dotIndex = originalFilename.lastIndexOf('.');
              if (dotIndex == -1) return false; // No extension
              final nameWithoutExt = originalFilename.substring(0, dotIndex);
              return f.startsWith('${nameWithoutExt}_');
            }, orElse: () => ''); // Return '' if not found

            if (serverFilename.isNotEmpty) {
              await _cacheFileBlob(recordIdForFiles, serverFilename, bytes);
            }
          }
        }
      }
      result = itemFactoryFunc(localRecordData);
    }

    if (result == null && requestPolicy == RequestPolicy.networkOnly) {
      throw Exception(
          'Failed to create record $body in $service and networkOnly policy was used.');
    }
    if (result == null && requestPolicy == RequestPolicy.cacheOnly) {
      // If cacheOnly, we should have a result from client.db.$create
      // This path should ideally not be hit if db.$create is successful
      throw Exception(
          'Failed to create record $body in $service for cacheOnly policy.');
    }
    // If result is still null here for cacheAndNetwork, it means both network and cache ops might have had issues
    // or the db.$create didn't return a usable item, which is unlikely if it doesn't throw.
    // However, if itemFactoryFunc needs a non-null map, this could be an issue.
    // For now, we assume db.$create always gives something itemFactoryFunc can use or throws.

    return result!; // Assuming result will be non-null if not networkOnly
  }

  @override
  Future<M> update(
    String id, {
    RequestPolicy requestPolicy = RequestPolicy.cacheAndNetwork,
    Map<String, dynamic> body = const {},
    Map<String, dynamic> query = const {},
    List<http.MultipartFile> files = const [],
    Map<String, String> headers = const {},
    String? expand,
    String? fields,
  }) async {
    // Buffer the raw file data immediately. A MultipartFile can only be read once.
    final List<(String field, String? filename, Uint8List bytes)>
        bufferedFilesData = [];
    if (files.isNotEmpty) {
      for (final file in files) {
        final bytes = await file.finalize().toBytes();
        bufferedFilesData.add((file.field, file.filename, bytes));
      }
    }

    M? result;
    bool savedToNetwork = false;
    Map<String, dynamic> recordDataForCache = Map.from(body);

    // For cache-only, we need to manually add filenames to the record data
    if (requestPolicy == RequestPolicy.cacheOnly) {
      for (final file in files) {
        // Find the corresponding buffered data to get the filename
        final fieldName = file.field;
        final filename = file.filename;
        if (filename == null) continue;

        // We MUST look up the schema to know if the field is multi-select.
        final collection =
            await client.db.$collections(service: service).getSingle();
        final schemaField =
            collection.fields.firstWhere((f) => f.name == fieldName);
        final isMultiSelect = schemaField.data['maxSelect'] != 1;

        final existing = recordDataForCache[fieldName];
        if (existing == null) {
          recordDataForCache[fieldName] = isMultiSelect ? [filename] : filename;
        } else if (existing is List) {
          existing.add(filename);
        } else {
          // It was a string, but now we have another file. This case shouldn't
          // happen if the schema is respected, but as a fallback, convert to list.
          recordDataForCache[fieldName] = [existing, filename];
        }
      }
    }

    if (requestPolicy.isNetwork && client.connectivity.isConnected) {
      try {
        result = await super.update(
          id,
          body: body,
          query: query,
          headers: headers,
          expand: expand,
          fields: fields,
          // Create fresh MultipartFile instances for the network call
          files: bufferedFilesData.map((d) {
            return http.MultipartFile.fromBytes(d.$1, d.$3, filename: d.$2);
          }).toList(),
        );
        savedToNetwork = true;
        recordDataForCache = result.toJson();
      } on ClientException catch (e) {
        if (e.statusCode == 404 || e.statusCode == 400) {
          // 400 might be "record not found" if ID is in body
          // If update failed with 404 (record not found), try to create
          try {
            result = await super.create(
              body: {
                ...body,
                'id': id
              }, // Ensure ID is part of the body for create
              query: query,
              headers: headers,
              expand: expand,
              fields: fields,
              // Create fresh MultipartFile instances for the network call
              files: bufferedFilesData.map((d) {
                return http.MultipartFile.fromBytes(d.$1, d.$3, filename: d.$2);
              }).toList(),
            );
            savedToNetwork = true;
            recordDataForCache = result.toJson();
          } catch (createE) {
            final msg =
                'Failed to update (then create) record $id in $service: $e, then $createE';
            if (requestPolicy == RequestPolicy.networkOnly) {
              throw Exception(msg);
            }
            debugPrint(msg);
          }
        } else {
          final msg = 'Failed to update record $id in $service: $e';
          if (requestPolicy == RequestPolicy.networkOnly) throw Exception(msg);
          debugPrint(msg);
        }
      } catch (e) {
        final msg = 'Failed to update record $id in $service: $e';
        if (requestPolicy == RequestPolicy.networkOnly) throw Exception(msg);
        debugPrint(msg);
      }
    }

    if (requestPolicy.isCache) {
      // Determine if this operation should be excluded from automatic sync.
      final shouldNoSync = requestPolicy == RequestPolicy.cacheOnly;
      final localRecordData = await client.db.$update(
        service,
        id,
        {
          'deleted': false,
          ...recordDataForCache,
          'synced': savedToNetwork,
          'isNew': false,
          'noSync': shouldNoSync,
        },
      );

      // Cache files associated with this update
      if (bufferedFilesData.isNotEmpty) {
        final recordIdForFiles = id;
        for (final fileData in bufferedFilesData) {
          final dynamic filenamesInRecord = recordDataForCache[fileData.$1];
          final bytes = fileData.$3; // Use bytes directly from buffer

          if (filenamesInRecord is String) {
            // Handle single file field
            await _cacheFileBlob(recordIdForFiles, filenamesInRecord, bytes);
          } else if (filenamesInRecord is List &&
              filenamesInRecord.isNotEmpty) {
            // Handle multi-file field by finding the matching original filename
            final originalFilename = fileData.$2;
            if (originalFilename == null) continue;

            final serverFilename = filenamesInRecord.firstWhere((f) {
              if (f is! String) return false;
              // Exact match (cacheOnly case)
              if (f == originalFilename) return true;

              // Check for server-renamed pattern
              final dotIndex = originalFilename.lastIndexOf('.');
              if (dotIndex == -1) return false; // No extension
              final nameWithoutExt = originalFilename.substring(0, dotIndex);
              return f.startsWith('${nameWithoutExt}_');
            }, orElse: () => ''); // Return '' if not found

            if (serverFilename.isNotEmpty) {
              await _cacheFileBlob(recordIdForFiles, serverFilename, bytes);
            }
          }
        }
      }
      result = itemFactoryFunc(localRecordData);
    }

    // Similar null checks and error throwing as in `create`
    if (result == null && requestPolicy == RequestPolicy.networkOnly) {
      throw Exception(
          'Failed to update record $id in $service and networkOnly policy was used.');
    }
    if (result == null && requestPolicy == RequestPolicy.cacheOnly) {
      throw Exception(
          'Failed to update record $id in $service for cacheOnly policy.');
    }

    return result!;
  }

  @override
  Future<void> delete(
    String id, {
    RequestPolicy requestPolicy = RequestPolicy.cacheAndNetwork,
    Map<String, dynamic> body = const {},
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
  }) async {
    bool saved = false;

    if (requestPolicy.isNetwork && client.connectivity.isConnected) {
      try {
        await super.delete(
          id,
          body: body,
          query: query,
          headers: headers,
        );
        saved = true;
      } catch (e) {
        final msg = 'Failed to delete record $id in $service: $e';
        if (requestPolicy == RequestPolicy.networkOnly) {
          throw Exception(msg);
        } else {
          debugPrint(msg);
        }
      }
    }

    if (requestPolicy.isCache) {
      if (saved) {
        await client.db.$delete(service, id);
      } else {
        await update(
          id,
          body: {
            ...body,
            'deleted': true,
          },
          query: query,
          headers: headers,
          requestPolicy: requestPolicy,
        );
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

enum RequestPolicy {
  cacheOnly,
  networkOnly,
  cacheAndNetwork,
}

extension RequestPolicyUtils on RequestPolicy {
  bool get isNetwork =>
      this == RequestPolicy.networkOnly ||
      this == RequestPolicy.cacheAndNetwork;
  bool get isCache =>
      this == RequestPolicy.cacheOnly || this == RequestPolicy.cacheAndNetwork;

  Future<T> fetch<T>({
    required String label,
    required $PocketBase client,
    required Future<T> Function() remote,
    required Future<T> Function() getLocal,
    required Future<void> Function(T) setLocal,
    // Duration timeout = const Duration(seconds: 3),
  }) async {
    client.logger.finer('Fetching "$label" with policy "$name"');
    T? result;

    if (isNetwork) {
      // Proactive connectivity check.
      if (!client.connectivity.isConnected) {
        client.logger
            .info('Device is offline. Skipping network request for "$label".');
        if (this == RequestPolicy.networkOnly) {
          throw Exception(
              'Device is offline and RequestPolicy.networkOnly was requested.');
        }
        // Fall through to cache if possible.
      } else {
        // Device is online, proceed with network request.
        try {
          client.logger.finer('Fetching remote for "$label"...');
          result = await remote();
        } catch (e) {
          client.logger.warning('Remote fetch for "$label" failed.', e);
          if (this == RequestPolicy.networkOnly) {
            throw Exception('Failed to get $e');
          }
        }
      }
    }

    if (isCache) {
      if (result != null) {
        client.logger.finer('Got remote data for "$label", updating cache...');
        await setLocal(result);
      } else {
        client.logger
            .finer('No remote data for "$label", fetching from cache...');
        result = await getLocal();
      }
    }

    if (result == null) {
      throw Exception('Failed to get');
    }

    return result;
  }
}
