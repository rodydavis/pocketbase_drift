import 'dart:convert';

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pocketbase_drift/pocketbase_drift.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fake_jwt.dart';
import '../test_data/collections.json.dart';

class _MockClient extends http.BaseClient {
  _MockClient(this.handler);
  final Future<http.Response> Function(http.BaseRequest request) handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await handler(request);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      request: request,
      headers: {'content-type': 'application/json'},
    );
  }
}

class _ConnectionRefused implements Exception {
  @override
  String toString() => 'SocketException: Connection refused';
}

const _collection = 'ultimate';
const _collectionId = 'p1fq7xv6lor6sx5';
const _id = 'rec_uncached01';

/// Deleting a record that is not in the local cache: the deletion is queued
/// as a bare tombstone and synced like any other offline deletion.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late $PocketBase client;
  late Map<String, Map<String, dynamic>> server;
  late List<String> deletes;

  /// Status to answer the next DELETE with (once).
  int? deleteFailure;

  /// Every request fails as if the server were not reachable.
  var refused = false;

  Map<String, dynamic> record(String id) => {
        'id': id,
        'collectionId': _collectionId,
        'collectionName': _collection,
        'created': '2026-11-04 10:00:00.000Z',
        'updated': '2026-11-04 10:00:00.000Z',
        'plain_text': 'server text',
      };

  Future<http.Response> handle(http.BaseRequest request) async {
    if (refused) throw _ConnectionRefused();
    final segments = request.url.path.split('/');
    final records = segments.indexOf('records');
    if (request.url.path == '/api/batch') {
      final body = jsonDecode((request as http.Request).body);
      final results = <Map<String, dynamic>>[];
      for (final r in body['requests'] as List) {
        final id = Uri.parse(r['url'] as String).pathSegments.last;
        if (r['method'] != 'DELETE' || server.remove(id) == null) {
          return http.Response('{"status":400,"message":"Batch failed"}', 400);
        }
        results.add({'status': 204, 'body': null});
      }
      return http.Response(jsonEncode(results), 200);
    }
    if (records == -1) return http.Response('{}', 404);
    final id = segments.length > records + 1 ? segments[records + 1] : null;
    switch (request.method) {
      case 'DELETE':
        deletes.add(id!);
        final failure = deleteFailure;
        deleteFailure = null;
        if (failure != null) {
          return http.Response(
              jsonEncode({'status': failure, 'message': 'rejected'}), failure);
        }
        if (server.remove(id) == null) {
          return http.Response('{"status":404}', 404);
        }
        return http.Response('', 204);
      case 'GET':
        if (id == null) {
          final items = server.values.toList();
          return http.Response(
              jsonEncode({
                'page': 1,
                'perPage': 500,
                'totalItems': items.length,
                'totalPages': 1,
                'items': items,
              }),
              200);
        }
        final existing = server[id];
        if (existing == null) return http.Response('{"status":404}', 404);
        return http.Response(jsonEncode(existing), 200);
    }
    return http.Response('{}', 404);
  }

  setUpAll(() {
    ConnectivityService.enableProbes = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async => ['wifi'],
    );
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    server = {};
    deletes = [];
    deleteFailure = null;
    refused = false;
    client = $PocketBase.database(
      'http://mock.pb',
      connection: DatabaseConnection(NativeDatabase.memory()),
      httpClientFactory: () => _MockClient(handle),
      localSyncRetryCount: 1,
      requestTimeout: const Duration(milliseconds: 300),
    );
    await client.db.setSchema(
      [...offlineCollections]
          .map((e) => jsonDecode(jsonEncode(e)) as Map<String, dynamic>)
          .toList(),
    );
    await client.syncCompleted;
    client.authStore.save(fakeJwt(), RecordModel({'id': 'account_a'}));
    await client.syncCompleted;
  });

  tearDown(() => client.close());

  $RecordService records() => client.collection(_collection);

  Future<Map<String, dynamic>?> row() => client.db.rowById(_collection, _id);

  Future<void> deleteOffline() async {
    client.connectivity.setConnectivityStatus(false);
    await records().delete(_id);
  }

  Future<void> reconnect() async {
    client.connectivity.setConnectivityStatus(true);
    await client.syncPendingChanges();
  }

  test('an offline delete of an uncached record syncs after reconnect',
      () async {
    server[_id] = record(_id);
    await deleteOffline();

    final pending = await client.db.pendingRecords().get();
    expect(pending.map((r) => r.id), [_id]);
    expect(pending.single.data[RecordMeta.deleted], true);
    expect(pending.single.data[RecordMeta.pendingOwner], 'account_a');

    await reconnect();
    expect(server.containsKey(_id), isFalse);
    expect(await row(), isNull);
  });

  test('an online cacheFirst delete of an uncached record reaches the server',
      () async {
    server[_id] = record(_id);
    await records().delete(_id, requestPolicy: RequestPolicy.cacheFirst);
    await client.syncCompleted;
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(deletes, [_id]);
    expect(server.containsKey(_id), isFalse);
    expect(await row(), isNull);
  });

  test('a server error queues the delete of an uncached record', () async {
    server[_id] = record(_id);
    deleteFailure = 503;
    await records().delete(_id);
    expect((await row())![RecordMeta.deleted], true);

    await client.syncPendingChanges();
    expect(server.containsKey(_id), isFalse);
  });

  test('an unreachable server queues the delete of an uncached record',
      () async {
    server[_id] = record(_id);
    refused = true;
    await records().delete(_id);
    expect((await row())![RecordMeta.deleted], true);

    refused = false;
    await reconnect();
    expect(server.containsKey(_id), isFalse);
  });

  test('the queued delete of a record the server no longer has ends quietly',
      () async {
    final failures = <SyncFailure>[];
    final sub = client.syncFailures.listen(failures.add);
    await deleteOffline();
    await reconnect();

    expect(deletes, [_id]);
    expect(await row(), isNull);
    expect(failures, isEmpty);
    await sub.cancel();
  });

  test('a rejected queued delete is parked and reported', () async {
    server[_id] = record(_id);
    final failures = <SyncFailure>[];
    final sub = client.syncFailures.listen(failures.add);
    await deleteOffline();
    deleteFailure = 403;
    await reconnect();
    await Future<void>.delayed(Duration.zero);

    expect(server.containsKey(_id), isTrue);
    expect((await row())![RecordMeta.syncError], isNotNull);
    expect(failures.single.operation, SyncOperation.delete);
    expect(failures.single.recordId, _id);
    await sub.cancel();
  });

  test('server reads before the sync do not bring the record back', () async {
    server[_id] = record(_id);
    await deleteOffline();
    client.connectivity.setConnectivityStatus(true);
    deleteFailure = 503; // the push triggered by the reads stays queued

    final one =
        await records().getOne(_id, requestPolicy: RequestPolicy.networkFirst);
    expect(one.id, _id, reason: 'the server still has it');
    await records().getFullList();
    await records().getList(perPage: 1);
    await records().onEvent(RecordSubscriptionEvent(
      action: 'update',
      record:
          RecordModel({...server[_id]!, 'updated': '2026-12-01 00:00:00.000Z'}),
    ));

    final cached =
        await records().getFullList(requestPolicy: RequestPolicy.cacheOnly);
    expect(cached.map((r) => r.id), isNot(contains(_id)));
    expect(await client.search('server').get(), isEmpty);
    final tombstone = (await row())!;
    expect(tombstone[RecordMeta.deleted], true);
    expect(tombstone[RecordMeta.synced], false);
  });

  test('cache maintenance keeps the queued delete', () async {
    server[_id] = record(_id);
    await deleteOffline();
    await client.runMaintenance(ttl: Duration.zero);
    await client.db.clearCache();

    expect((await row())![RecordMeta.deleted], true);
    await reconnect();
    expect(server.containsKey(_id), isFalse);
  });

  test('an offline batch delete of an uncached record is queued', () async {
    server[_id] = record(_id);
    client.connectivity.setConnectivityStatus(false);
    final batch = client.$createBatch();
    batch.collection(_collection).delete(_id);

    final results = await batch.send();
    expect(results.single.status, 204);

    await reconnect();
    expect(server.containsKey(_id), isFalse);
  });

  test('another account does not sync the queued delete', () async {
    server[_id] = record(_id);
    await deleteOffline();
    client.authStore.clear();
    client.authStore.save(fakeJwt(), RecordModel({'id': 'account_b'}));
    await Future<void>.delayed(Duration.zero);
    await reconnect();
    expect(server.containsKey(_id), isTrue);

    client.authStore.save(fakeJwt(), RecordModel({'id': 'account_a'}));
    await Future<void>.delayed(Duration.zero);
    await client.syncCompleted;
    expect(server.containsKey(_id), isFalse);
  });

  test('a cacheOnly delete of an uncached record changes nothing', () async {
    server[_id] = record(_id);
    await records().delete(_id, requestPolicy: RequestPolicy.cacheOnly);

    expect(await row(), isNull);
    expect(await client.db.pendingRecords().get(), isEmpty);
  });
}
