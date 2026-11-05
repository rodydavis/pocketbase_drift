import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pocketbase_drift/pocketbase_drift.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_data/collections.json.dart';

class _Sent {
  _Sent(this.method, this.path, this.query, this.body);
  final String method;
  final String path;
  final Map<String, String> query;
  final Map<String, dynamic> body;

  @override
  String toString() => '$method $path $query $body';
}

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

/// Fields PocketBase never returns (hidden / write-only).
const _hidden = {'password', 'passwordConfirm', 'oldPassword'};

/// Completion of batch sends and pushes when the server answers with a
/// different form of a field (dates), without a field (hidden auth fields,
/// `fields` projections), or while the record changes locally.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late $PocketBase client;
  late Map<String, Map<String, dynamic>> server;
  late List<_Sent> sent;
  Completer<void>? batchGate;

  /// When set, the next single-record request of that method waits.
  late Map<String, Completer<void>> gates;
  var clock = 0;

  String nextUpdated() =>
      '2026-11-05 10:00:${(clock++ % 60).toString().padLeft(2, '0')}.000Z';

  /// PocketBase stores a date as `YYYY-MM-DD HH:MM:SS.sssZ`.
  Object? normalize(String key, Object? value) =>
      key == 'datetime' && value is String && value.length == 10
          ? '$value 00:00:00.000Z'
          : value;

  void apply(Map<String, dynamic> target, Map<String, dynamic> body) {
    for (final e in body.entries) {
      final key = e.key;
      if (key == 'id') continue;
      final name = key.replaceAll(RegExp(r'^\+|[+-]$'), '');
      if (name == key) {
        target[key] = normalize(key, e.value);
        continue;
      }
      final current = target[name];
      if (current is num || name == 'number') {
        final a = (current as num?) ?? 0;
        target[name] =
            key.endsWith('-') ? a - (e.value as num) : a + (e.value as num);
        continue;
      }
      final list = [...(current as List? ?? const [])];
      final values = e.value is List ? e.value as List : [e.value];
      if (key.endsWith('-')) {
        list.removeWhere(values.contains);
      } else {
        for (final v in values) {
          if (!list.contains(v)) list.add(v);
        }
      }
      target[name] = list;
    }
  }

  /// Response body: hidden fields removed, `fields` projection applied.
  Map<String, dynamic> respond(
      Map<String, dynamic> record, Map<String, String> query) {
    final out = {
      for (final e in record.entries)
        if (!_hidden.contains(e.key)) e.key: e.value,
    };
    final fields = query['fields'];
    if (fields == null || fields.isEmpty) return out;
    final keep = fields.split(',').map((f) => f.trim()).toSet();
    return {
      for (final e in out.entries)
        if (keep.contains(e.key)) e.key: e.value,
    };
  }

  /// Like PocketBase: a password change of an auth record needs
  /// `oldPassword` (non-superuser).
  Map<String, dynamic>? reject(String collection, Map<String, dynamic> body) {
    if (collection == 'users' &&
        body.containsKey('password') &&
        !body.containsKey('oldPassword')) {
      return {
        'status': 400,
        'message': 'Failed to update record.',
        'data': {
          'oldPassword': {
            'code': 'validation_required',
            'message': 'Missing required value.'
          }
        },
      };
    }
    return null;
  }

  ({int status, Object? body}) run(String method, String collection, String? id,
      Map<String, dynamic> body, Map<String, String> query) {
    switch (method) {
      case 'POST':
        final newId = body['id'] as String;
        final record = <String, dynamic>{
          'id': newId,
          'collectionName': collection,
          'created': '2026-11-05 09:00:00.000Z',
          'updated': nextUpdated(),
        };
        apply(record, body);
        server[newId] = record;
        return (status: 200, body: respond(record, query));
      case 'PATCH':
        final existing = server[id];
        if (existing == null) return (status: 404, body: {'status': 404});
        final error = reject(collection, body);
        if (error != null) return (status: 400, body: error);
        final next = {...existing};
        apply(next, body);
        next['updated'] = nextUpdated();
        server[id!] = next;
        return (status: 200, body: respond(next, query));
      case 'DELETE':
        if (server.remove(id) == null) {
          return (status: 404, body: {'status': 404});
        }
        return (status: 204, body: null);
    }
    return (status: 404, body: {'status': 404});
  }

  Future<http.Response> handle(http.BaseRequest raw) async {
    Map<String, dynamic> body = {};
    if (raw is http.Request && raw.body.isNotEmpty) {
      body = jsonDecode(raw.body) as Map<String, dynamic>;
    }
    final request =
        _Sent(raw.method, raw.url.path, raw.url.queryParameters, body);
    sent.add(request);
    if (request.path == '/api/batch') {
      final gate = batchGate;
      if (gate != null) {
        batchGate = null;
        await gate.future;
      }
      final results = <Map<String, dynamic>>[];
      for (final r in body['requests'] as List) {
        final url = Uri.parse(r['url'] as String);
        final segs = url.pathSegments;
        final collection = segs[segs.indexOf('collections') + 1];
        final id = segs.last == 'records' ? null : segs.last;
        final b = ((r['body'] as Map?) ?? const {}).cast<String, dynamic>();
        final res =
            run(r['method'] as String, collection, id, b, url.queryParameters);
        results.add({'status': res.status, 'body': res.body});
      }
      return http.Response(jsonEncode(results), 200);
    }
    final gate = gates.remove(request.method);
    if (gate != null) await gate.future;
    final segs = request.path.split('/');
    final records = segs.indexOf('records');
    if (records == -1) return http.Response('{}', 404);
    final collection = segs[records - 1];
    final id = segs.length > records + 1 ? segs[records + 1] : null;
    if (request.method == 'GET') {
      final existing = server[id];
      if (existing == null) return http.Response('{"status":404}', 404);
      return http.Response(jsonEncode(respond(existing, request.query)), 200);
    }
    final res = run(request.method, collection, id, body, request.query);
    return http.Response(
        res.body == null ? '' : jsonEncode(res.body), res.status);
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
    sent = [];
    batchGate = null;
    gates = {};
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
  });

  tearDown(() => client.close());

  List<_Sent> writes() => sent.where((s) => s.method != 'GET').toList();

  Future<void> sendBatch(
      RequestPolicy policy, void Function($BatchService batch) add) async {
    final batch = client.$createBatch();
    add(batch);
    await batch.send(requestPolicy: policy);
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }

  Future<void> seed(String id, Map<String, dynamic> data) async {
    server[id] = {
      'id': id,
      'collectionName': _collection,
      'created': '2026-11-04 10:00:00.000Z',
      'updated': '2026-11-04 10:00:00.000Z',
      ...data,
    };
    await client.db.upsertServerRecords(_collection, [server[id]!]);
  }

  $RecordService records([String name = _collection]) =>
      client.collection(name);

  group('a field the batch sent is done', () {
    test('cacheFirst create with a date the server normalises', () async {
      await sendBatch(
          RequestPolicy.cacheFirst,
          (b) => b.collection(_collection).create(body: {
                'id': 'rec_create00001',
                'plain_text': 'x',
                'datetime': '2026-01-01',
              }));
      final row = (await client.db.rowById(_collection, 'rec_create00001'))!;
      expect(row[RecordMeta.synced], isTrue);
      expect(row[RecordMeta.pendingFields], isNull);
      expect(row['datetime'], '2026-01-01 00:00:00.000Z');
      await records().pushPending('rec_create00001');
      expect(writes(), hasLength(1));
    });

    test('cacheFirst create of an auth record with a hidden password',
        () async {
      final failures = <SyncFailure>[];
      final sub = client.syncFailures.listen(failures.add);
      addTearDown(sub.cancel);
      await sendBatch(
          RequestPolicy.cacheFirst,
          (b) => b.collection('users').create(body: {
                'id': 'usr_create00001',
                'email': 'a@b.co',
                'name': 'n',
                'password': '12345678',
                'passwordConfirm': '12345678',
              }));
      final row = (await client.db.rowById('users', 'usr_create00001'))!;
      expect(row[RecordMeta.synced], isTrue);
      expect(row.containsKey('password'), isFalse);
      await records('users').pushPending('usr_create00001');
      expect(writes(), hasLength(1));
      expect(failures, isEmpty);
    });

    for (final policy in [
      RequestPolicy.cacheFirst,
      RequestPolicy.cacheAndNetwork,
      RequestPolicy.networkFirst,
    ]) {
      test('${policy.name} update of a date the server normalises', () async {
        await seed('rec_update00001', {'datetime': '', 'plain_text': 'v0'});
        await sendBatch(
            policy,
            (b) => b
                .collection(_collection)
                .update('rec_update00001', body: {'datetime': '2026-01-01'}));
        final row = (await client.db.rowById(_collection, 'rec_update00001'))!;
        expect(row[RecordMeta.synced], isTrue,
            reason: 'pending: ${row[RecordMeta.pendingFields]}');
        expect(row['datetime'], '2026-01-01 00:00:00.000Z');
        await records().pushPending('rec_update00001');
        expect(writes(), hasLength(1));
      });
    }

    test(
        'cacheFirst update keeps an earlier queued field and drops the sent '
        'date', () async {
      await seed('rec_update00002', {'datetime': '', 'plain_text': 'v0'});
      await records()
          .writeLocalUpdate('rec_update00002', {'plain_text': 'q'}, sync: true);
      await sendBatch(
          RequestPolicy.cacheFirst,
          (b) => b
              .collection(_collection)
              .update('rec_update00002', body: {'datetime': '2026-01-01'}));
      final row = (await client.db.rowById(_collection, 'rec_update00002'))!;
      expect(row[RecordMeta.pendingFields], ['plain_text']);
      expect(row['datetime'], '2026-01-01 00:00:00.000Z');
      await records().pushPending('rec_update00002');
      expect(writes().last.body, {'plain_text': 'q'});
    });

    test(
        'a push of a create with an edit made meanwhile does not resend the '
        'hidden password', () async {
      final failures = <SyncFailure>[];
      final sub = client.syncFailures.listen(failures.add);
      addTearDown(sub.cancel);
      await records('users').writeLocalCreate({
        'id': 'usr_create00002',
        'email': 'c@d.co',
        'name': 'n',
        'password': '12345678',
        'passwordConfirm': '12345678',
      }, sync: true);
      final gate = gates['POST'] = Completer<void>();
      final push = records('users').pushPending('usr_create00002');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await records('users')
          .writeLocalUpdate('usr_create00002', {'name': 'm'}, sync: true);
      gate.complete();
      await push;
      await records('users').pushPending('usr_create00002');

      expect(writes().last.body, {'name': 'm'});
      expect(failures, isEmpty);
      final row = (await client.db.rowById('users', 'usr_create00002'))!;
      expect(row[RecordMeta.synced], isTrue);
    });
  });

  group('a response without the field (fields projection)', () {
    setUp(() => seed('rec_proj000001', {
          'number': 10,
          'select_multi': ['a'],
          'plain_text': 'v0',
        }));

    test('cacheFirst batch keeps modifier results and other fields', () async {
      await sendBatch(
          RequestPolicy.cacheFirst,
          (b) => b.collection(_collection).update('rec_proj000001',
              body: {
                'number+': 1,
                'select_multi+': ['b']
              },
              fields: 'id'));
      expect(server['rec_proj000001']!['number'], 11);
      final cached = (await client.db.rowById(_collection, 'rec_proj000001'))!;
      expect(cached['number'], 11);
      expect(cached['select_multi'], ['a', 'b']);
      expect(cached['plain_text'], 'v0');
      expect(cached[RecordMeta.synced], isTrue);

      await records().pushPending('rec_proj000001');
      expect(writes(), hasLength(1));
      expect(server['rec_proj000001']!['number'], 11);
      expect(server['rec_proj000001']!['select_multi'], ['a', 'b']);
    });

    test('a projected push keeps the record and a delta made meanwhile',
        () async {
      await records()
          .writeLocalUpdate('rec_proj000001', {'number+': 1}, sync: true);
      final gate = gates['PATCH'] = Completer<void>();
      final push = records()
          .pushPending('rec_proj000001', query: const {'fields': 'id'});
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await records()
          .writeLocalUpdate('rec_proj000001', {'number+': 2}, sync: true);
      gate.complete();
      await push;

      final between = (await client.db.rowById(_collection, 'rec_proj000001'))!;
      expect(between['plain_text'], 'v0');
      expect(between['number'], 13);
      expect(between[RecordMeta.pendingBase], {'number': 11});

      await records().pushPending('rec_proj000001');
      expect(writes().map((w) => w.body), [
        {'number+': 1},
        {'number+': 2},
      ]);
      expect(server['rec_proj000001']!['number'], 13);
      final after = (await client.db.rowById(_collection, 'rec_proj000001'))!;
      expect(after['number'], 13);
      expect(after['plain_text'], 'v0');
    });
  });

  group('an edit made while an online batch is in flight', () {
    test('back to the value before the batch is kept', () async {
      await seed('rec_toggle0001', {'bool': false});
      final gate = batchGate = Completer<void>();
      final batch = client.$createBatch();
      batch
          .collection(_collection)
          .update('rec_toggle0001', body: {'bool': true});
      final send = batch.send(requestPolicy: RequestPolicy.cacheAndNetwork);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await records().update('rec_toggle0001',
          body: {'bool': false}, requestPolicy: RequestPolicy.cacheFirst);
      gate.complete();
      await send;
      await records().pushPending('rec_toggle0001');

      expect(server['rec_toggle0001']!['bool'], isFalse);
      expect((await client.db.rowById(_collection, 'rec_toggle0001'))!['bool'],
          isFalse);
    });

    test('a field queued before the batch still loses to it', () async {
      await seed('rec_toggle0002', {'bool': false, 'plain_text': 'v0'});
      await records()
          .writeLocalUpdate('rec_toggle0002', {'bool': true}, sync: true);
      final gate = batchGate = Completer<void>();
      final batch = client.$createBatch();
      batch
          .collection(_collection)
          .update('rec_toggle0002', body: {'bool': false});
      final send = batch.send(requestPolicy: RequestPolicy.cacheAndNetwork);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await records()
          .writeLocalUpdate('rec_toggle0002', {'plain_text': 'x'}, sync: true);
      gate.complete();
      await send;
      await records().pushPending('rec_toggle0002');

      expect(writes().last.body, {'plain_text': 'x'});
      expect(server['rec_toggle0002']!['bool'], isFalse);
    });
  });
}
