import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:http/http.dart' as http;

import 'package:pocketbase_drift/pocketbase_drift.dart';

/// Represents the reactive state of a query, bundling cached data with
/// network fetching status and any error encountered during remote synchronization.
class QueryState<T> {
  const QueryState({
    required this.data,
    required this.isFetchingNetwork,
    this.error,
  });

  /// The latest cached or fetched data.
  final T data;

  /// Whether a background network request is currently active.
  final bool isFetchingNetwork;

  /// The error encountered during the most recent network fetch, if any.
  final Object? error;

  /// Whether an error occurred during the most recent network fetch.
  bool get hasError => error != null;

  QueryState<T> copyWith({
    T? data,
    bool? isFetchingNetwork,
    Object? error,
  }) {
    return QueryState<T>(
      data: data ?? this.data,
      isFetchingNetwork: isFetchingNetwork ?? this.isFetchingNetwork,
      error: error ?? this.error,
    );
  }
}

class $RecordService extends RecordService with ServiceMixin<RecordModel> {
  $RecordService(this.client, this.service) : super(client, service);

  @override
  final $PocketBase client;

  @override
  final String service;

  Selectable<RecordModel> search(String query) {
    return client.db.search(query, service: service).map(
          (p0) => itemFactoryFunc({
            ...p0.data,
            'created': p0.created,
            'updated': p0.updated,
            'id': p0.id,
          }),
        );
  }

  Selectable<RecordModel> pending() {
    // Fetches records that are unsynced AND are NOT marked as local-only.
    // Tombstones (offline deletes) are included so retryLocal can sync them.
    return client.db
        .$query(service,
            includeDeleted: true,
            filter: "synced = false && (noSync = null || noSync = false)")
        .map(itemFactoryFunc);
  }

  Stream<RetryProgressEvent?> retryLocal({
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
    int? batch,
  }) async* {
    final items = await pending().get();
    final total = items.length;

    client.logger
        .info('Starting retry for $total pending items in service: $service');
    yield RetryProgressEvent(current: 0, total: total);

    if (total == 0) {
      return;
    }

    // Get the collection schema to identify file fields
    final collection =
        await client.db.$collections(service: service).getSingleOrNull();
    final fileFieldNames = collection?.fields
            .where((f) => f.type == 'file')
            .map((f) => f.name)
            .toList() ??
        [];

    for (var i = 0; i < total; i++) {
      final item = items[i];
      try {
        final tempId = item.id;
        client.logger.fine('Retrying item $tempId (${i + 1}/$total)');

        // The record was marked for deletion while offline.
        if (item.data['deleted'] == true) {
          if (item.data['isNew'] == true) {
            // Created offline and deleted before it ever reached the server:
            // there is nothing on the server to delete, so purge locally.
            await client.db.$delete(service, tempId);
            client.logger.fine(
                'Purged item $tempId that was created and deleted offline (never synced)');
          } else {
            try {
              await delete(
                tempId,
                requestPolicy: RequestPolicy.networkFirst,
                query: query,
                headers: headers,
              );
              client.logger.fine('Successfully synced deletion for item $tempId');
            } on ClientException catch (e) {
              if (e.statusCode == 404) {
                // Already gone on the server (e.g. deleted from another
                // device). Drop the local tombstone instead of retrying 404s
                // forever.
                await client.db.$delete(service, tempId);
                client.logger.fine(
                    'Item $tempId already deleted on server; removed local tombstone');
              } else {
                rethrow;
              }
            }
          }

          // The record was newly created offline.
        } else if (item.data['isNew'] == true) {
          // Prepare body for creation by removing server-generated and local-only fields.
          final createBody = Map<String, dynamic>.from(item.toJson());
          createBody.remove('created');
          createBody.remove('updated');
          createBody.remove('collectionId');
          createBody.remove('collectionName');
          createBody.remove('expand');
          createBody.remove('synced');
          createBody.remove('isNew');
          createBody.remove('deleted');
          createBody.remove('noSync');

          // Get cached files for this record
          final files =
              await _getFilesForSync(tempId, item.data, fileFieldNames);

          // Also remove file field names from body since they'll be sent as multipart files
          // (The server generates new filenames anyway)
          for (final fieldName in fileFieldNames) {
            createBody.remove(fieldName);
          }

          // Create the record on the server with our local ID.
          await create(
            body: createBody,
            files: files,
            requestPolicy: RequestPolicy.networkFirst,
            query: query,
            headers: headers,
          );
          client.logger.fine(
              'Successfully synced new item with ID ${item.id} (${files.length} files)');

          // The record was an existing one that was updated offline.
        } else {
          // Get cached files for this record
          final files =
              await _getFilesForSync(tempId, item.data, fileFieldNames);

          // Prepare update body - don't include file field names
          final updateBody = Map<String, dynamic>.from(item.toJson());
          for (final fieldName in fileFieldNames) {
            updateBody.remove(fieldName);
          }

          try {
            await update(
              tempId,
              body: updateBody,
              files: files,
              requestPolicy: RequestPolicy.networkFirst,
              query: query,
              headers: headers,
            );
            client.logger.fine(
                'Successfully synced update for item $tempId (${files.length} files)');
          } on ClientException catch (e) {
            if (e.statusCode == 404) {
              // The record no longer exists on the server (deleted from
              // another device while we were offline). Recreating it would
              // be wrong, so drop the stale local copy instead of retrying
              // 404s forever.
              await client.db.$delete(service, tempId);
              client.logger.warning(
                  'Item $tempId no longer exists on server; removed stale local copy');
            } else {
              rethrow;
            }
          }
        }
      } on ClientException catch (e) {
        // Handle 400 Bad Request errors specifically (Validation errors, Orphans, etc.)
        if (e.statusCode == 400) {
          final response = e.response;
          final responseStr = response.toString();

          // Implement a max-retry mechanism for all 400 errors
          var retryCount = (item.data['retryCount'] as num?)?.toInt() ?? 0;
          retryCount++;

          final maxRetries = client.localSyncRetryCount;

          if (retryCount >= maxRetries) {
            client.logger.severe(
                'Sync failed for item ${item.id}: Exceeded max retries ($retryCount/$maxRetries). '
                'Deleting stuck record. Error: $responseStr',
                e);

            // Delete the stuck record locally to unblock the queue
            await client.db.$delete(service, item.id);
            continue;
          }

          // Verify if record still exists before updating to avoid race conditions
          final exists = await client.db
              .$query(service,
                  filter: "id = '${item.id}'", includeDeleted: true)
              .getSingleOrNull();
          if (exists != null) {
            client.logger.warning(
                'Sync failed for item ${item.id} (Attempt $retryCount/$maxRetries). Error: $responseStr',
                e);

            // Update the retry count in the local record
            // We use direct DB update to avoid triggering another "isNew" or Sync event
            await client.db.$update(
              service,
              item.id,
              {
                ...item.data,
                'retryCount': retryCount,
              },
              validate: false,
            );
          }
        } else {
          client.logger.warning(
              'Error retrying local change for item ${item.id} (Status: ${e.statusCode})',
              e);
        }
      } catch (e) {
        client.logger
            .warning('Error retrying local change for item ${item.id}', e);
        // Continue with other items even if one fails
      }
      yield RetryProgressEvent(current: i + 1, total: total);
    }

    client.logger.info('Completed retry for service: $service');
  }

  /// Retrieves cached file blobs for a record and converts them to MultipartFile.
  ///
  /// This method looks at the file field values in the record data to determine
  /// which files need to be synced, then fetches them from the local blob cache.
  Future<List<http.MultipartFile>> _getFilesForSync(
    String recordId,
    Map<String, dynamic> recordData,
    List<String> fileFieldNames,
  ) async {
    final files = <http.MultipartFile>[];

    if (fileFieldNames.isEmpty) return files;

    // Get all cached files for this record
    final cachedFiles = await client.db.getFilesForRecord(recordId).get();
    if (cachedFiles.isEmpty) return files;

    // Create a map for quick lookup by filename
    final fileByName = {for (final f in cachedFiles) f.filename: f};

    for (final fieldName in fileFieldNames) {
      final dynamic fieldValue = recordData[fieldName];
      if (fieldValue == null) continue;

      // Handle single file field
      if (fieldValue is String && fieldValue.isNotEmpty) {
        final cachedFile = fileByName[fieldValue];
        if (cachedFile != null) {
          files.add(http.MultipartFile.fromBytes(
            fieldName,
            cachedFile.data,
            filename: cachedFile.filename,
          ));
          client.logger.fine(
              'Including file "${cachedFile.filename}" for field "$fieldName" in sync');
        }
      }
      // Handle multi-file field
      else if (fieldValue is List) {
        for (final filename in fieldValue.whereType<String>()) {
          if (filename.isEmpty) continue;
          final cachedFile = fileByName[filename];
          if (cachedFile != null) {
            files.add(http.MultipartFile.fromBytes(
              fieldName,
              cachedFile.data,
              filename: cachedFile.filename,
            ));
            client.logger.fine(
                'Including file "${cachedFile.filename}" for field "$fieldName" in sync');
          }
        }
      }
    }

    return files;
  }

  @override
  Future<UnsubscribeFunc> subscribe(
    String topic,
    RecordSubscriptionFunc callback, {
    String? expand,
    String? filter,
    String? fields,
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
  }) {
    return super.subscribe(
      topic,
      (e) {
        onEvent(e);
        callback(e);
      },
      expand: expand,
      filter: filter,
      fields: fields,
      query: query,
      headers: headers,
    );
  }

  Future<void> onEvent(RecordSubscriptionEvent e) async {
    if (e.record != null) {
      if (e.action == 'create') {
        await client.db.$create(
          service,
          {
            ...e.record!.toJson(),
            'deleted': false,
            'synced': true,
          },
        );
      } else if (e.action == 'update') {
        await client.db.$update(
          service,
          e.record!.id,
          {
            ...e.record!.toJson(),
            'deleted': false,
            'synced': true,
          },
        );
      } else if (e.action == 'delete') {
        await client.db.$delete(
          service,
          e.record!.id,
        );
      }
    }
  }

  Stream<RecordModel?> watchRecord(
    String id, {
    String? expand,
    String? fields,
    RequestPolicy? requestPolicy,
    bool distinctResults = true,
  }) {
    final policy = resolvePolicy(requestPolicy);
    UnsubscribeFunc? unsub;
    StreamSubscription<RecordModel?>? dbSubscription;
    var cancelled = false;
    var stream = client.db
        .$query(
          service,
          filter: "id = '$id'",
          expand: expand,
          fields: fields,
        )
        .map(itemFactoryFunc)
        .watchSingleOrNull();

    if (distinctResults) {
      stream = stream.distinct((prev, next) {
        if (prev == null && next == null) return true;
        if (prev == null || next == null) return false;
        return prev.id == next.id &&
            prev.get('updated') == next.get('updated') &&
            jsonEncode(prev.data['expand']) == jsonEncode(next.data['expand']);
      });
    }

    late final StreamController<RecordModel?> controller;
    controller = StreamController<RecordModel?>(
      onListen: () async {
        cancelled = false;
        dbSubscription = stream.listen(
          (data) {
            if (!controller.isClosed) controller.add(data);
          },
          onError: (Object e, StackTrace st) {
            if (!controller.isClosed) controller.addError(e, st);
          },
        );

        if (policy.isNetwork) {
          try {
            final result = await subscribe(id, (e) {});
            if (cancelled) {
              await result.call();
            } else {
              unsub = result;
            }
          } catch (e) {
            client.logger
                .warning('Error subscribing to record $service/$id', e);
          }
        }

        try {
          await getOneOrNull(id,
              expand: expand, fields: fields, requestPolicy: policy);
        } catch (e, st) {
          if (!controller.isClosed) controller.addError(e, st);
        }
      },
      onPause: () => dbSubscription?.pause(),
      onResume: () => dbSubscription?.resume(),
      onCancel: () async {
        cancelled = true;
        try {
          await dbSubscription?.cancel();
        } finally {
          if (policy.isNetwork) {
            try {
              await unsub?.call();
            } catch (e) {
              client.logger.fine(
                  'Error unsubscribing from record $service/$id (may be intentional)',
                  e);
            }
          }
        }
      },
    );
    return controller.stream;
  }

  Stream<List<RecordModel>> watchRecords({
    String? expand,
    String? filter,
    String? sort,
    int? limit,
    String? fields,
    RequestPolicy? requestPolicy,
    bool distinctResults = true,
  }) {
    final policy = resolvePolicy(requestPolicy);
    UnsubscribeFunc? unsub;
    StreamSubscription<List<RecordModel>>? dbSubscription;
    var cancelled = false;
    var stream = client.db
        .$query(
          service,
          filter: filter,
          expand: expand,
          sort: sort,
          limit: limit,
          fields: fields,
        )
        .map(itemFactoryFunc)
        .watch();

    if (distinctResults) {
      stream = stream.distinct((prev, next) {
        if (prev.length != next.length) return false;
        for (var i = 0; i < prev.length; i++) {
          if (prev[i].id != next[i].id ||
              prev[i].get('updated') != next[i].get('updated') ||
              jsonEncode(prev[i].data['expand']) !=
                  jsonEncode(next[i].data['expand'])) {
            return false;
          }
        }
        return true;
      });
    }

    late final StreamController<List<RecordModel>> controller;
    controller = StreamController<List<RecordModel>>(
      onListen: () async {
        cancelled = false;
        dbSubscription = stream.listen(
          (data) {
            if (!controller.isClosed) controller.add(data);
          },
          onError: (Object e, StackTrace st) {
            if (!controller.isClosed) controller.addError(e, st);
          },
        );

        if (policy.isNetwork) {
          try {
            final result = await subscribe('*', (e) {});
            if (cancelled) {
              await result.call();
            } else {
              unsub = result;
            }
          } catch (e) {
            client.logger
                .warning('Error subscribing to collection $service', e);
          }
        }

        try {
          final items = await getFullList(
            requestPolicy: policy,
            filter: filter,
            expand: expand,
            sort: sort,
            fields: fields,
          );
          client.logger.fine(
              'Realtime initial full list for "$service" [${policy.name}]: ${items.length} items');
        } catch (e, st) {
          if (!controller.isClosed) controller.addError(e, st);
        }
      },
      onPause: () => dbSubscription?.pause(),
      onResume: () => dbSubscription?.resume(),
      onCancel: () async {
        cancelled = true;
        try {
          await dbSubscription?.cancel();
        } finally {
          if (policy.isNetwork) {
            try {
              await unsub?.call();
            } catch (e) {
              client.logger.fine(
                  'Error unsubscribing from collection $service (may be intentional)',
                  e);
            }
          }
        }
      },
    );
    return controller.stream;
  }

  Stream<QueryState<RecordModel?>> watchRecordState(
    String id, {
    String? expand,
    String? fields,
    RequestPolicy? requestPolicy,
    bool distinctResults = true,
  }) {
    final policy = resolvePolicy(requestPolicy);
    UnsubscribeFunc? unsub;
    bool isFetchingNetwork = policy.isNetwork;
    StreamSubscription<RecordModel?>? dbSubscription;
    RecordModel? latestData;
    var cancelled = false;

    final stream = client.db
        .$query(
          service,
          filter: "id = '$id'",
          expand: expand,
          fields: fields,
        )
        .map(itemFactoryFunc)
        .watchSingleOrNull();

    late final StreamController<QueryState<RecordModel?>> controller;
    controller = StreamController<QueryState<RecordModel?>>(
      onListen: () async {
        cancelled = false;
        Object? fetchError;

        dbSubscription = stream.listen((data) {
          latestData = data;
          if (!controller.isClosed) {
            controller.add(QueryState(
              data: data,
              isFetchingNetwork: isFetchingNetwork,
              error: fetchError,
            ));
          }
        });

        if (policy.isNetwork) {
          try {
            final result = await subscribe(id, (e) {});
            if (cancelled) {
              await result.call();
            } else {
              unsub = result;
            }
          } catch (e) {
            client.logger
                .warning('Error subscribing to record $service/$id', e);
          }
        }

        try {
          await getOneOrNull(id,
              expand: expand, fields: fields, requestPolicy: policy);
        } catch (e, st) {
          fetchError = e;
          if (!controller.isClosed) controller.addError(e, st);
        } finally {
          if (isFetchingNetwork) {
            isFetchingNetwork = false;
            if (!controller.isClosed) {
              controller.add(QueryState(
                data: latestData,
                isFetchingNetwork: false,
                error: fetchError,
              ));
            }
          }
        }
      },
      onPause: () => dbSubscription?.pause(),
      onResume: () => dbSubscription?.resume(),
      onCancel: () async {
        cancelled = true;
        try {
          await dbSubscription?.cancel();
        } finally {
          if (policy.isNetwork) {
            try {
              await unsub?.call();
            } catch (e) {
              client.logger.fine(
                  'Error unsubscribing from record $service/$id (may be intentional)',
                  e);
            }
          }
        }
      },
    );

    if (distinctResults) {
      return controller.stream.distinct((prev, next) {
        if (prev.isFetchingNetwork != next.isFetchingNetwork) return false;
        if (prev.error != next.error) return false;
        final pData = prev.data;
        final nData = next.data;
        if (pData == null && nData == null) return true;
        if (pData == null || nData == null) return false;
        return pData.id == nData.id &&
            pData.get('updated') == nData.get('updated') &&
            jsonEncode(pData.data['expand']) ==
                jsonEncode(nData.data['expand']);
      });
    }

    return controller.stream;
  }

  Stream<QueryState<List<RecordModel>>> watchRecordsState({
    String? expand,
    String? filter,
    String? sort,
    int? limit,
    String? fields,
    RequestPolicy? requestPolicy,
    bool distinctResults = true,
  }) {
    final policy = resolvePolicy(requestPolicy);
    UnsubscribeFunc? unsub;
    bool isFetchingNetwork = policy.isNetwork;
    StreamSubscription<List<RecordModel>>? dbSubscription;
    List<RecordModel> latestData = [];
    var cancelled = false;

    final stream = client.db
        .$query(
          service,
          filter: filter,
          expand: expand,
          sort: sort,
          limit: limit,
          fields: fields,
        )
        .map(itemFactoryFunc)
        .watch();

    late final StreamController<QueryState<List<RecordModel>>> controller;
    controller = StreamController<QueryState<List<RecordModel>>>(
      onListen: () async {
        cancelled = false;
        Object? fetchError;

        dbSubscription = stream.listen((data) {
          latestData = data;
          if (!controller.isClosed) {
            controller.add(QueryState(
              data: data,
              isFetchingNetwork: isFetchingNetwork,
              error: fetchError,
            ));
          }
        });

        if (policy.isNetwork) {
          try {
            final result = await subscribe('*', (e) {});
            if (cancelled) {
              await result.call();
            } else {
              unsub = result;
            }
          } catch (e) {
            client.logger
                .warning('Error subscribing to collection $service', e);
          }
        }

        try {
          final items = await getFullList(
            requestPolicy: policy,
            filter: filter,
            expand: expand,
            sort: sort,
            fields: fields,
          );
          client.logger.fine(
              'Realtime initial full list for "$service" [${policy.name}]: ${items.length} items');
        } catch (e, st) {
          fetchError = e;
          if (!controller.isClosed) controller.addError(e, st);
        } finally {
          if (isFetchingNetwork) {
            isFetchingNetwork = false;
            if (!controller.isClosed) {
              controller.add(QueryState(
                data: latestData,
                isFetchingNetwork: false,
                error: fetchError,
              ));
            }
          }
        }
      },
      onPause: () => dbSubscription?.pause(),
      onResume: () => dbSubscription?.resume(),
      onCancel: () async {
        cancelled = true;
        try {
          await dbSubscription?.cancel();
        } finally {
          if (policy.isNetwork) {
            try {
              await unsub?.call();
            } catch (e) {
              client.logger.fine(
                  'Error unsubscribing from collection $service (may be intentional)',
                  e);
            }
          }
        }
      },
    );

    if (distinctResults) {
      return controller.stream.distinct((prev, next) {
        if (prev.isFetchingNetwork != next.isFetchingNetwork) return false;
        if (prev.error != next.error) return false;
        final pData = prev.data;
        final nData = next.data;
        if (pData.length != nData.length) return false;
        for (var i = 0; i < pData.length; i++) {
          if (pData[i].id != nData[i].id ||
              pData[i].get('updated') != nData[i].get('updated') ||
              jsonEncode(pData[i].data['expand']) !=
                  jsonEncode(nData[i].data['expand'])) {
            return false;
          }
        }
        return true;
      });
    }

    return controller.stream;
  }
}
