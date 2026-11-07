import 'dart:async';
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

const _collection = 'ultimate';
const _collectionId = 'p1fq7xv6lor6sx5';
const _owner = 'account_a';

/// With an expired token PocketBase answers as a guest: owner-scoped list
/// rules return no rows, and reads, updates and deletes of the account's
/// records get 404. The package must not take those answers for the
/// account's data or drop queued changes on them.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late $PocketBase client;
  late Map<String, Map<String, dynamic>> server;
  late List<String> requests;
  late String validToken;

  Map<String, dynamic> record(String id, [String text = 'server text']) => {
        'id': id,
        'collectionId': _collectionId,
        'collectionName': _collection,
        'created': '2026-11-04 10:00:00.000Z',
        'updated': '2026-11-04 10:00:00.000Z',
        'plain_text': text,
      };

  http.Response json(Object body, [int status = 200]) =>
      http.Response(jsonEncode(body), status);

  Future<http.Response> handle(http.BaseRequest request) async {
    final segments = request.url.pathSegments;
    final at = segments.indexOf('records');
    if (at == -1) return json({}, 404);
    final id = segments.length > at + 1 ? segments[at + 1] : null;
    requests.add('${request.method} ${id ?? 'list'}');
    final guest = request.headers['Authorization'] != validToken;
    final notFound = json({'status': 404, 'message': 'Not found.'}, 404);
    switch (request.method) {
      case 'GET' when id == null:
        final items = guest ? <Map<String, dynamic>>[] : server.values.toList();
        return json({
          'page': 1,
          'perPage': 1000,
          'totalItems': -1,
          'totalPages': -1,
          'items': items,
        });
      case 'GET':
        final existing = server[id];
        return guest || existing == null ? notFound : json(existing);
      case 'PATCH':
        final existing = server[id];
        if (guest || existing == null) return notFound;
        final body = jsonDecode((request as http.Request).body) as Map;
        return json(server[id!] = {
          ...existing,
          ...body.cast<String, dynamic>(),
          'updated': '2026-11-05 10:00:00.000Z',
        });
      case 'DELETE':
        if (guest || server.remove(id) == null) return notFound;
        return http.Response('', 204);
      case 'POST':
        if (guest) return json({'status': 400, 'message': 'Failed.'}, 400);
        final body = jsonDecode((request as http.Request).body) as Map;
        final created = {
          ...record(body['id'] as String),
          ...body.cast<String, dynamic>(),
        };
        return json(server[created['id'] as String] = created);
    }
    return json({}, 404);
  }

  void login() {
    validToken = fakeJwt();
    client.authStore.save(validToken, RecordModel({'id': _owner}));
  }

  void expire() => client.authStore.save(
        fakeJwt(expires: DateTime.now().subtract(const Duration(minutes: 1))),
        RecordModel({'id': _owner}),
      );

  $RecordService records() => client.collection(_collection);

  Future<List<String>> cachedIds() async => [
        for (final r in await records()
            .getFullList(sort: 'id', requestPolicy: RequestPolicy.cacheOnly))
          r.id
      ];

  Future<List<String>> pendingIds() async =>
      [for (final r in await client.db.pendingRecords().get()) r.id];

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
    server = {'rec_session001': record('rec_session001')};
    server['rec_session002'] = record('rec_session002');
    requests = [];
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
    login();
    await client.syncCompleted;
    await records().getFullList();
    expect(await cachedIds(), ['rec_session001', 'rec_session002']);
    requests.clear();
  });

  tearDown(() => client.close());

  test('reads with an expired session answer from the cache and keep it',
      () async {
    expire();
    expect(client.hasExpiredSession, isTrue);

    for (final policy in [
      RequestPolicy.cacheAndNetwork,
      RequestPolicy.networkFirst,
      RequestPolicy.cacheFirst,
    ]) {
      final list = await records().getFullList(requestPolicy: policy);
      expect(list.map((r) => r.id), hasLength(2), reason: policy.name);
      final one =
          await records().getOne('rec_session001', requestPolicy: policy);
      expect(one.id, 'rec_session001');
    }
    final miss = await records()
        .getOne('rec_uncached01')
        .then<Object>((r) => r, onError: (Object e) => e);
    expect(miss,
        isA<ClientException>().having((e) => e.statusCode, 'status', 401));

    expect(requests, isEmpty);
    expect(await cachedIds(), ['rec_session001', 'rec_session002']);
  });

  test('a queued change waits while the session is expired, then syncs',
      () async {
    final failures = <SyncFailure>[];
    final sub = client.syncFailures.listen(failures.add);
    addTearDown(sub.cancel);

    client.connectivity.setConnectivityStatus(false);
    await records().update('rec_session001', body: {'plain_text': 'edited'});
    await records().delete('rec_session002');
    expire();
    client.connectivity.setConnectivityStatus(true);
    await client.syncPendingChanges();
    expect(
        await records().pushPending('rec_session001'), PushOutcome.retryLater);

    expect(requests, isEmpty);
    expect(failures, isEmpty);
    expect(await pendingIds(),
        unorderedEquals(['rec_session001', 'rec_session002']));

    login();
    await Future<void>.delayed(Duration.zero);
    await client.syncCompleted;
    expect(await pendingIds(), isEmpty);
    expect(server['rec_session001']!['plain_text'], 'edited');
    expect(server.containsKey('rec_session002'), isFalse);
  });

  test('cacheAndNetwork writes with an expired session are queued', () async {
    expire();
    await records().update('rec_session001', body: {'plain_text': 'edited'});
    await records().delete('rec_session002');
    final created = await records().create(body: {'plain_text': 'new'});

    expect(requests, isEmpty);
    expect(await pendingIds(),
        unorderedEquals(['rec_session001', 'rec_session002', created.id]));

    login();
    await Future<void>.delayed(Duration.zero);
    await client.syncCompleted;
    expect(await pendingIds(), isEmpty);
    expect(server.keys, unorderedEquals(['rec_session001', created.id]));
  });

  test('a strict update answered 404 with an expired session keeps the cache',
      () async {
    expire();
    final error = await records()
        .update('rec_session001',
            body: {'plain_text': 'edited'},
            requestPolicy: RequestPolicy.networkOnly)
        .then<Object>((r) => r, onError: (Object e) => e);
    expect(error,
        isA<ClientException>().having((e) => e.statusCode, 'status', 404));
    expect(requests, ['PATCH rec_session001']);
    expect(await cachedIds(), ['rec_session001', 'rec_session002']);
  });

  test('onSessionExpired emits once until a valid login', () async {
    var events = 0;
    final sub = client.onSessionExpired.listen((_) => events++);
    addTearDown(sub.cancel);

    expire();
    await records().getFullList();
    await client.syncPendingChanges();
    await Future<void>.delayed(Duration.zero);
    expect(events, 1);

    login();
    await Future<void>.delayed(Duration.zero);
    await client.syncCompleted;
    await records().getFullList();
    expect(events, 1);

    expire();
    await records().getFullList();
    await Future<void>.delayed(Duration.zero);
    expect(events, 2);
  });

  test('a guest without a token reads from the server', () async {
    client.authStore.clear();
    await Future<void>.delayed(Duration.zero);
    expect(client.hasExpiredSession, isFalse);
    expect(await records().getFullList(), isEmpty);
    expect(requests, ['GET list']);
  });
}
