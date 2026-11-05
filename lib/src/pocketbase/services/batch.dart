import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../pocketbase_drift.dart';
import 'sync_support.dart';

/// A request queued in a batch operation.
///
/// This class stores all the information needed to either send the request
/// to the server or apply it to the local cache.
class $BatchRequest {
  /// The HTTP method for this request (POST, PATCH, PUT, DELETE).
  final String method;

  /// The collection this request targets.
  final String collection;

  /// The record ID: set for update/delete, and assigned on the client for
  /// creates and upserts without an `id`, so a retried batch or a later
  /// individual sync cannot create duplicates.
  final String? recordId;

  /// The request body data.
  final Map<String, dynamic> body;

  /// Query parameters.
  final Map<String, dynamic> query;

  /// Request headers.
  final Map<String, String> headers;

  /// Files to upload, buffered in memory so they can be replayed offline.
  final List<(String field, String? filename, Uint8List bytes)> files;

  /// Expand parameter for the request.
  final String? expand;

  /// Fields parameter for limiting response fields.
  final String? fields;

  const $BatchRequest({
    required this.method,
    required this.collection,
    this.recordId,
    this.body = const {},
    this.query = const {},
    this.headers = const {},
    this.files = const [],
    this.expand,
    this.fields,
  });

  /// Whether this is a create operation.
  bool get isCreate => method == 'POST';

  /// Whether this is an update operation.
  bool get isUpdate => method == 'PATCH';

  /// Whether this is an upsert operation.
  bool get isUpsert => method == 'PUT';

  /// Whether this is a delete operation.
  bool get isDelete => method == 'DELETE';
}

/// Result of a single batch operation.
///
/// Maps to the PocketBase BatchResult but with additional information
/// about which collection/record the result corresponds to.
class $BatchResult {
  /// HTTP status code of the operation.
  final int status;

  /// The response body (usually a RecordModel or error details).
  final dynamic body;

  /// The collection this result corresponds to.
  final String collection;

  /// The record ID (if applicable).
  final String? recordId;

  /// Whether the operation was successful (2xx status).
  bool get isSuccess => status >= 200 && status < 300;

  /// Whether the operation failed.
  bool get isError => !isSuccess;

  const $BatchResult({
    required this.status,
    required this.body,
    required this.collection,
    this.recordId,
  });

  /// Attempts to parse the body as a RecordModel.
  /// Returns null if parsing fails or body is not a valid record.
  RecordModel? get record {
    if (body is Map<String, dynamic>) {
      try {
        return RecordModel.fromJson(body as Map<String, dynamic>);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  @override
  String toString() =>
      '\$BatchResult(status: $status, collection: $collection, recordId: $recordId)';
}

class _Queued {
  _Queued(this.request, this.uploads);

  $BatchRequest request;
  final List<http.MultipartFile> uploads;
}

/// A sub-service for queuing batch operations on a specific collection.
///
/// This class provides methods to queue create, update, delete, and upsert
/// operations that will be executed together when [send] is called on the
/// parent [$BatchService].
class $SubBatchService {
  final $BatchService _batch;
  final String _collection;

  $SubBatchService(this._batch, this._collection);

  String _idOf(Map<String, dynamic> body) {
    final id = body['id'];
    return id is String && id.isNotEmpty ? id : newId();
  }

  /// Queues a record create operation.
  ///
  /// The actual creation will happen when [send] is called on the parent batch.
  void create({
    Map<String, dynamic> body = const {},
    Map<String, dynamic> query = const {},
    List<http.MultipartFile> files = const [],
    Map<String, String> headers = const {},
    String? expand,
    String? fields,
  }) {
    final id = _idOf(body);
    _batch._addRequest(
      $BatchRequest(
        method: 'POST',
        collection: _collection,
        recordId: id,
        body: {...body, 'id': id},
        query: Map.from(query),
        headers: Map.from(headers),
        expand: expand,
        fields: fields,
      ),
      files,
    );
  }

  /// Queues a record update operation.
  ///
  /// The actual update will happen when [send] is called on the parent batch.
  void update(
    String recordId, {
    Map<String, dynamic> body = const {},
    Map<String, dynamic> query = const {},
    List<http.MultipartFile> files = const [],
    Map<String, String> headers = const {},
    String? expand,
    String? fields,
  }) {
    _batch._addRequest(
      $BatchRequest(
        method: 'PATCH',
        collection: _collection,
        recordId: recordId,
        body: Map.from(body),
        query: Map.from(query),
        headers: Map.from(headers),
        expand: expand,
        fields: fields,
      ),
      files,
    );
  }

  /// Queues a record delete operation.
  ///
  /// The actual deletion will happen when [send] is called on the parent batch.
  void delete(
    String recordId, {
    Map<String, dynamic> body = const {},
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
  }) {
    _batch._addRequest(
      $BatchRequest(
        method: 'DELETE',
        collection: _collection,
        recordId: recordId,
        body: Map.from(body),
        query: Map.from(query),
        headers: Map.from(headers),
      ),
      const [],
    );
  }

  /// Queues a record upsert operation.
  ///
  /// The request will be executed as update if `body` contains a valid existing
  /// record `id` value, otherwise it will be executed as create.
  ///
  /// The actual operation will happen when [send] is called on the parent batch.
  void upsert({
    Map<String, dynamic> body = const {},
    Map<String, dynamic> query = const {},
    List<http.MultipartFile> files = const [],
    Map<String, String> headers = const {},
    String? expand,
    String? fields,
  }) {
    final id = _idOf(body);
    _batch._addRequest(
      $BatchRequest(
        method: 'PUT',
        collection: _collection,
        recordId: id,
        body: {...body, 'id': id},
        query: Map.from(query),
        headers: Map.from(headers),
        expand: expand,
        fields: fields,
      ),
      files,
    );
  }
}

/// A service for executing batch/transactional operations with offline support.
///
/// This service allows you to queue multiple create, update, delete, and upsert
/// operations across different collections and execute them in a single request.
///
/// When used with [RequestPolicy.cacheAndNetwork] (default), if the server
/// cannot be reached, all operations are stored locally and will be retried
/// as individual operations when connectivity is restored. A batch the
/// server rejects (e.g. a validation error) throws [ClientException] and
/// nothing is stored.
///
/// Example:
/// ```dart
/// final batch = client.$createBatch();
///
/// batch.collection('posts').create(body: {'title': 'Hello'});
/// batch.collection('posts').update('abc123', body: {'title': 'Updated'});
/// batch.collection('comments').delete('def456');
///
/// final results = await batch.send();
/// for (final result in results) {
///   if (result.isSuccess) {
///     print('Success: ${result.collection}/${result.recordId}');
///   }
/// }
/// ```
class $BatchService {
  final $PocketBase client;
  final List<_Queued> _queue = [];
  final Map<String, $SubBatchService> _subs = {};

  $BatchService(this.client);

  List<$BatchRequest> get _requests => [for (final q in _queue) q.request];

  /// Returns a sub-service for queuing batch operations on a specific collection.
  $SubBatchService collection(String collectionIdOrName) =>
      _subs[collectionIdOrName] ??= $SubBatchService(this, collectionIdOrName);

  /// Adds a request to the batch queue.
  void _addRequest($BatchRequest request, List<http.MultipartFile> uploads) {
    _queue.add(_Queued(request, uploads));
  }

  /// Returns the number of queued requests.
  int get length => _queue.length;

  /// Returns true if there are no queued requests.
  bool get isEmpty => _queue.isEmpty;

  /// Reads queued uploads into memory (a multipart stream can be read once).
  Future<void> _bufferUploads() async {
    for (final q in _queue) {
      if (q.uploads.isEmpty) continue;
      final files = <(String, String?, Uint8List)>[...q.request.files];
      for (final file in q.uploads) {
        files.add((file.field, file.filename, await file.finalize().toBytes()));
      }
      q.uploads.clear();
      final r = q.request;
      q.request = $BatchRequest(
        method: r.method,
        collection: r.collection,
        recordId: r.recordId,
        body: r.body,
        query: r.query,
        headers: r.headers,
        files: files,
        expand: r.expand,
        fields: r.fields,
      );
    }
  }

  bool get _hasFiles => _queue.any((q) => q.request.files.isNotEmpty);

  /// Sends all queued batch requests.
  ///
  /// The [requestPolicy] determines how the batch is handled:
  /// - [RequestPolicy.networkOnly]: Send to server only, throw on failure.
  /// - [RequestPolicy.cacheOnly]: Apply all operations to local cache only.
  /// - [RequestPolicy.networkFirst]: Send to server, then update the cache;
  ///   throw on failure (no fallback).
  /// - [RequestPolicy.cacheFirst]: Apply to cache as pending, send the batch
  ///   in the background; failed operations sync individually later.
  /// - [RequestPolicy.cacheAndNetwork]: Send to server; store the operations
  ///   as pending only when the server is unreachable.
  ///
  /// Returns a list of [$BatchResult] objects, one for each queued request.
  Future<List<$BatchResult>> send({
    RequestPolicy requestPolicy = RequestPolicy.cacheAndNetwork,
    Map<String, dynamic> body = const {},
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
  }) async {
    if (_queue.isEmpty) {
      return [];
    }
    await _bufferUploads();

    return switch (requestPolicy) {
      RequestPolicy.cacheOnly => _applyAllToCache(sync: false),
      RequestPolicy.networkOnly => _sendNetworkOnly(body, query, headers),
      RequestPolicy.networkFirst => _sendNetworkFirst(body, query, headers),
      RequestPolicy.cacheFirst => _sendCacheFirst(body, query, headers),
      RequestPolicy.cacheAndNetwork =>
        _sendCacheAndNetwork(body, query, headers),
    };
  }

  void _requireNetwork(RequestPolicy policy) {
    if (!client.connectivity.shouldAttemptNetwork) {
      throw ClientException(
        statusCode: 0,
        response: {
          'message':
              'No network connection; ${policy.name} batch send needs the server.',
        },
      );
    }
  }

  /// Sends batch to server only. Throws if offline or request fails.
  Future<List<$BatchResult>> _sendNetworkOnly(
    Map<String, dynamic> body,
    Map<String, dynamic> query,
    Map<String, String> headers,
  ) async {
    _requireNetwork(RequestPolicy.networkOnly);
    await _pushReferencedCreates();
    return _sendOnline(body, query, headers, cache: false);
  }

  /// `collection/id` of every record the batch writes.
  List<String> get _recordKeys => [
        for (final request in _requests)
          if ((request.recordId ?? request.body['id']) case final String id)
            '${request.collection}/$id',
      ];

  /// Sends the batch once running pushes of its records are done and blocks
  /// their pushes until the results are cached (see [runOnline]).
  Future<List<$BatchResult>> _sendOnline(
    Map<String, dynamic> body,
    Map<String, dynamic> query,
    Map<String, String> headers, {
    required bool cache,
  }) =>
      runOnline(client, _recordKeys, client.requestTimeout, () async {
        final results = await _sendToServer(body, query, headers);
        if (cache) await _syncResultsToCache(results);
        return results;
      });

  /// Pushes the queued creates of records this batch updates or deletes:
  /// the server rejects the whole batch when one of them does not exist
  /// there yet. Returns false when one of them still is not on the server
  /// (each push is awaited at most `requestTimeout`).
  Future<bool> _pushReferencedCreates() async {
    var pushed = true;
    final wait = client.requestTimeout;
    for (final request in _requests) {
      final id = request.recordId;
      if (id == null || !(request.isUpdate || request.isDelete)) continue;
      final row = await client.db.rowById(request.collection, id);
      if (row == null ||
          !RecordMeta.isPending(row) ||
          !RecordMeta.flag(row[RecordMeta.isNew])) {
        continue;
      }
      final push = client.collection(request.collection).pushPending(id);
      final outcome = wait == null
          ? await push
          : await push.timeout(wait, onTimeout: () => PushOutcome.retryLater);
      if (outcome != PushOutcome.synced) pushed = false;
    }
    return pushed;
  }

  /// Tries server first, throws on failure (no cache fallback).
  Future<List<$BatchResult>> _sendNetworkFirst(
    Map<String, dynamic> body,
    Map<String, dynamic> query,
    Map<String, String> headers,
  ) async {
    _requireNetwork(RequestPolicy.networkFirst);
    await _pushReferencedCreates();
    return _sendOnline(body, query, headers, cache: true);
  }

  /// Applies to cache first, tries server in background.
  Future<List<$BatchResult>> _sendCacheFirst(
    Map<String, dynamic> body,
    Map<String, dynamic> query,
    Map<String, String> headers,
  ) async {
    final results = await _applyAllToCache(sync: true);

    if (client.connectivity.canReachServer) {
      final revs = <String, int?>{
        for (final r in results)
          if (r.recordId != null && r.body is Map)
            '${r.collection}/${r.recordId}':
                ((r.body as Map)[RecordMeta.pendingRev] as num?)?.toInt(),
      };
      // Holds the records like a push, so sync does not send them again
      // and a delete meanwhile is queued instead of dropped.
      unawaited(runForRecords(
        client,
        revs.keys,
        () => _sendToServer(body, query, headers).then(
            (serverResults) => _syncResultsToCache(serverResults, revs: revs)),
      ).catchError((Object e) {
        client.logger.warning(
            'Background batch send failed; the operations sync individually.',
            e);
        // A rejected batch fails as a whole; the valid operations can still
        // sync on their own.
        if (!isTransientError(e)) unawaited(client.syncPendingChanges());
      }));
    } else {
      client.connectivity.probeSoon();
    }

    return results;
  }

  /// Tries server first, falls back to caching for pending sync when the
  /// server is unreachable.
  Future<List<$BatchResult>> _sendCacheAndNetwork(
    Map<String, dynamic> body,
    Map<String, dynamic> query,
    Map<String, String> headers,
  ) async {
    if (client.connectivity.canReachServer) {
      if (await _pushReferencedCreates()) {
        try {
          return await _sendOnline(body, query, headers, cache: true);
        } catch (e) {
          if (!isTransientError(e)) rethrow;
          client.logger.info('Batch queued for sync (server unavailable): $e');
        }
      }
    } else {
      client.connectivity.probeSoon();
    }
    final results = await _applyAllToCache(sync: true);
    client.logger.info(
        'Batch of ${_queue.length} requests saved to local cache for later sync.');
    return results;
  }

  Future<List<$BatchResult>> _applyAllToCache({required bool sync}) async {
    final results = <$BatchResult>[];
    for (final request in _requests) {
      try {
        results.add(await _applySingleToCache(request, sync: sync));
      } catch (e) {
        client.logger.warning(
            'Error applying batch request to cache: ${request.collection}', e);
        results.add($BatchResult(
          status: 500,
          body: {'error': e.toString()},
          collection: request.collection,
          recordId: request.recordId,
        ));
      }
    }
    return results;
  }

  /// Sends the batch request to the PocketBase server.
  Future<List<$BatchResult>> _sendToServer(
    Map<String, dynamic> body,
    Map<String, dynamic> query,
    Map<String, String> headers,
  ) async {
    // Build the batch using the SDK's BatchService
    final sdkBatch = client.createBatch();
    final requests = _requests;

    for (final request in requests) {
      final subBatch = sdkBatch.collection(request.collection);

      final enrichedQuery = Map<String, dynamic>.from(request.query);
      if (request.expand != null) enrichedQuery['expand'] = request.expand;
      if (request.fields != null) enrichedQuery['fields'] = request.fields;
      final files = [
        for (final f in request.files)
          http.MultipartFile.fromBytes(f.$1, f.$3, filename: f.$2),
      ];

      switch (request.method) {
        case 'POST':
          subBatch.create(
            body: request.body,
            query: enrichedQuery,
            headers: request.headers,
            files: files,
          );
        case 'PATCH':
          subBatch.update(
            request.recordId!,
            body: request.body,
            query: enrichedQuery,
            headers: request.headers,
            files: files,
          );
        case 'PUT':
          subBatch.upsert(
            body: request.body,
            query: enrichedQuery,
            headers: request.headers,
            files: files,
          );
        case 'DELETE':
          subBatch.delete(
            request.recordId!,
            body: request.body,
            query: request.query,
            headers: request.headers,
          );
      }
    }

    final List<BatchResult> sdkResults;
    try {
      final send = sdkBatch.send(body: body, query: query, headers: headers);
      final timeout = client.requestTimeout;
      sdkResults = timeout == null || _hasFiles
          ? await send
          : await send.timeout(timeout);
      client.connectivity.reportNetworkSuccess();
    } catch (e) {
      if (isConnectivityFailure(e)) {
        client.connectivity.reportNetworkFailure();
      } else if (e is ClientException) {
        client.connectivity.reportNetworkSuccess();
      }
      if (isTransientError(e)) throw toNetworkError(e);
      rethrow;
    }

    // Map SDK results to our results with collection/recordId info
    final results = <$BatchResult>[];
    for (var i = 0; i < sdkResults.length && i < requests.length; i++) {
      final sdkResult = sdkResults[i];
      final request = requests[i];

      results.add($BatchResult(
        status: sdkResult.status.toInt(),
        body: sdkResult.body,
        collection: request.collection,
        recordId: _extractIdFromBody(sdkResult.body) ?? request.recordId,
      ));
    }

    return results;
  }

  /// Applies a single batch request to the local cache. With [sync] the
  /// change is queued for the server, otherwise it stays local-only.
  Future<$BatchResult> _applySingleToCache(
    $BatchRequest request, {
    required bool sync,
  }) async {
    final service = client.collection(request.collection);

    if (request.isDelete) {
      final found =
          await service.writeLocalDelete(request.recordId!, sync: sync);
      return $BatchResult(
        status: found ? 204 : 404,
        body: null,
        collection: request.collection,
        recordId: request.recordId,
      );
    }

    final RecordModel record;
    var status = 200;
    final id = request.recordId;
    final exists =
        id != null && await client.db.rowById(request.collection, id) != null;
    if (request.isUpdate || (request.isUpsert && exists)) {
      final body = Map<String, dynamic>.of(request.body)..remove('id');
      record = await service.writeLocalUpdate(id!, body,
          files: request.files, sync: sync);
    } else {
      record = await service.writeLocalCreate(request.body,
          files: request.files, sync: sync);
      status = 201;
    }

    return $BatchResult(
      status: status,
      body: record.toJson(),
      collection: request.collection,
      recordId: record.id,
    );
  }

  /// Writes successful server results to the local cache. [revs] holds the
  /// pending revisions written by a `cacheFirst` send, so local changes made
  /// while the batch was in flight are kept.
  Future<void> _syncResultsToCache(
    List<$BatchResult> results, {
    Map<String, int?> revs = const {},
  }) async {
    final requests = _requests;
    for (var i = 0; i < results.length && i < requests.length; i++) {
      final result = results[i];
      final request = requests[i];
      final id = result.recordId;
      if (!result.isSuccess || id == null) continue;

      try {
        if (request.isDelete) {
          await client.db.$delete(request.collection, id);
          continue;
        }
        final data = result.body;
        if (data is! Map<String, dynamic>) continue;
        final key = '${request.collection}/$id';
        if (revs.containsKey(key)) {
          await client.db.completePendingSync(
            request.collection,
            id,
            revs[key],
            data,
            sentFiles: [
              for (final f in request.files)
                if (f.$2 != null) {'field': f.$1, 'name': f.$2},
            ],
            sentBody: request.body,
          );
        } else if (request.isCreate) {
          await client.db.upsertServerRecords(
            request.collection,
            [data],
            partial: request.fields?.isNotEmpty ?? false,
          );
        } else {
          // Queued local changes of the fields this request set are older.
          await client.db.acceptServerWrite(
            request.collection,
            id,
            data,
            {
              for (final k in request.body.keys)
                if (k != 'id') k,
              for (final f in request.files)
                if (baseFieldName(f.$1) == f.$1) f.$1,
            },
            partial: request.fields?.isNotEmpty ?? false,
          );
        }
      } catch (e) {
        client.logger.warning(
            'Error syncing batch result to cache: ${request.collection}', e);
      }
    }
  }

  /// Extracts the ID from a batch result body if possible.
  String? _extractIdFromBody(dynamic body) {
    if (body is Map<String, dynamic>) {
      return body['id'] as String?;
    }
    return null;
  }
}
