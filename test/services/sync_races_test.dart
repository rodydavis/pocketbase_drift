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

/// A request the fake server received.
class _Sent {
  _Sent(this.method, this.path, this.body, this.files);
  final String method;
  final String path;
  final Map<String, dynamic> body;
  final List<(String field, String? filename)> files;

  @override
  String toString() => '$method $path $body $files';
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
const _collectionId = 'p1fq7xv6lor6sx5';

/// Sync of pending changes while other changes of the same record happen:
/// pushes in flight, online writes, deletions and account switches
/// (2026-11-04 review findings).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late $PocketBase client;
  late Map<String, Map<String, dynamic>> server;
  late List<_Sent> sent;

  /// When set, the next request of that method waits for the completer.
  late Map<String, Completer<void>> gates;

  /// Status to answer the next request of that method with (once).
  late Map<String, int> failures;

  var fileCounter = 0;

  Map<String, dynamic> record(String id, Map<String, dynamic> data) => {
        'id': id,
        'collectionId': _collectionId,
        'collectionName': _collection,
        'created': '2026-11-04 10:00:00.000Z',
        'updated': '2026-11-04 10:00:00.000Z',
        ...data,
      };

  Future<_Sent> read(http.BaseRequest request) async {
    Map<String, dynamic> body = {};
    final files = <(String, String?)>[];
    if (request is http.Request) {
      if (request.body.isNotEmpty) body = jsonDecode(request.body);
    } else {
      final dynamic multipart = request;
      final fields = multipart.fields as Map;
      final payload = fields['@jsonPayload'];
      if (payload is List && payload.isNotEmpty) {
        body = jsonDecode(payload.first as String);
      }
      for (final f in multipart.files as List<http.MultipartFile>) {
        files.add((f.field, f.filename));
      }
    }
    return _Sent(request.method, request.url.path, body, files);
  }

  /// Applies uploads like PocketBase: generated names, `+` appends.
  void applyFiles(Map<String, dynamic> target, _Sent request) {
    for (final (field, filename) in request.files) {
      final base = field.replaceAll(RegExp(r'[+-]'), '');
      final dot = filename!.lastIndexOf('.');
      final name = '${filename.substring(0, dot)}_gen${fileCounter++}'
          '${filename.substring(dot)}';
      final current = target[base];
      if (base == 'file_single') {
        target[base] = name;
      } else {
        target[base] = [
          if (current is List && field.endsWith('+')) ...current,
          name
        ];
      }
    }
  }

  Future<http.Response> handle(http.BaseRequest raw) async {
    final request = await read(raw);
    sent.add(request);
    final gate = gates.remove(request.method);
    if (gate != null) await gate.future;
    final status = failures.remove(request.method);
    if (status != null) {
      return http.Response(
          jsonEncode({'status': status, 'message': 'rejected', 'data': {}}),
          status);
    }

    final segments = request.path.split('/');
    final records = segments.indexOf('records');
    if (request.path == '/api/batch') {
      final results = <Map<String, dynamic>>[];
      for (final r in request.body['requests'] as List) {
        final url = Uri.parse(r['url'] as String);
        final parts = url.path.split('/');
        final id = parts.length > 5 ? parts[5] : null;
        final body =
            Map<String, dynamic>.of((r['body'] as Map?)?.cast() ?? const {});
        switch (r['method']) {
          case 'PATCH':
            if (!server.containsKey(id)) {
              return http.Response(
                  jsonEncode({'status': 400, 'message': 'Batch failed'}), 400);
            }
            server[id!] = {...server[id]!, ...body};
            results.add({'status': 200, 'body': server[id]});
          case 'DELETE':
            if (server.remove(id) == null) {
              return http.Response(
                  jsonEncode({'status': 400, 'message': 'Batch failed'}), 400);
            }
            results.add({'status': 204, 'body': null});
        }
      }
      return http.Response(jsonEncode(results), 200);
    }
    if (records == -1) return http.Response('{}', 404);
    final id = segments.length > records + 1 ? segments[records + 1] : null;

    switch (request.method) {
      case 'POST':
        final newId = request.body['id'] as String;
        if (server.containsKey(newId)) {
          return http.Response(
              jsonEncode({
                'status': 400,
                'message': 'Failed to create record.',
                'data': {
                  'id': {'code': 'validation_invalid_id', 'message': 'taken'}
                },
              }),
              400);
        }
        final created = record(newId, {...request.body});
        applyFiles(created, request);
        server[newId] = created;
        return http.Response(jsonEncode(created), 200);
      case 'PATCH':
        final existing = server[id];
        if (existing == null) return http.Response('{"status":404}', 404);
        final next = {...existing, ...request.body};
        applyFiles(next, request);
        server[id!] = next;
        return http.Response(jsonEncode(next), 200);
      case 'DELETE':
        if (server.remove(id) == null) {
          return http.Response('{"status":404}', 404);
        }
        return http.Response('', 204);
      case 'GET':
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
    sent = [];
    gates = {};
    failures = {};
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

  $RecordService records() => client.collection(_collection);

  /// A record that exists on the server and is cached as synced.
  Future<void> seedSynced(String id, Map<String, dynamic> data) async {
    server[id] = record(id, data);
    await client.db.upsertServerRecords(_collection, [server[id]!]);
  }

  Future<Map<String, dynamic>?> row(String id) =>
      client.db.rowById(_collection, id);

  List<_Sent> writes() => sent.where((s) => s.method != 'GET').toList();

  test('an online update supersedes the same fields of a queued edit',
      () async {
    await seedSynced('rec_online0001', {'plain_text': 'v0', 'number': 0});
    await client.db.writeLocalUpdate(
        _collection, 'rec_online0001', {'plain_text': 'queued', 'number': 7},
        sync: true);

    await records().update('rec_online0001',
        body: {'plain_text': 'online'},
        requestPolicy: RequestPolicy.networkFirst);

    final cached = await row('rec_online0001');
    expect(cached!['plain_text'], 'online');
    expect(cached[RecordMeta.pendingFields], ['number'],
        reason: 'only the field the online write did not set stays queued');

    await records().pushPending('rec_online0001');
    expect(server['rec_online0001']!['plain_text'], 'online');
    expect(server['rec_online0001']!['number'], 7);
    expect(writes().last.body, {'number': 7});
  });

  test('an online update during a long upload push is queued behind it',
      () async {
    await seedSynced('rec_longpush01', {'plain_text': 'v0', 'file_multi': []});
    await records().writeLocalUpdate(
      'rec_longpush01',
      {'plain_text': 'queued'},
      files: [
        ('file_multi+', 'big.jpg', Uint8List.fromList([7]))
      ],
      sync: true,
    );

    final gate = gates['PATCH'] = Completer<void>();
    final push = records().pushPending('rec_longpush01');
    await Future<void>.delayed(const Duration(milliseconds: 20));

    // Uploads have no timeout; the online write waits 300 ms, then queues.
    final local = await records().update('rec_longpush01',
        body: {'plain_text': 'latest'},
        requestPolicy: RequestPolicy.cacheAndNetwork);
    expect(local.data['plain_text'], 'latest');
    expect(writes().length, 1, reason: 'nothing was sent past the push');

    gate.complete();
    await push;
    await records().pushPending('rec_longpush01');

    expect(server['rec_longpush01']!['plain_text'], 'latest');
    expect((await row('rec_longpush01'))!['plain_text'], 'latest');
    expect((await row('rec_longpush01'))![RecordMeta.synced], true);
  });

  test('an edit of a 0.6.x pending row during its push is kept', () async {
    await seedSynced('rec_legacy0002', {'plain_text': 'v0', 'number': 0});
    await client.db.$create(
        _collection,
        {
          ...(await row('rec_legacy0002'))!,
          'plain_text': 'offline edit',
          RecordMeta.synced: false,
          RecordMeta.isNew: false,
          RecordMeta.deleted: false,
        },
        validate: false);

    final gate = gates['PATCH'] = Completer<void>();
    final push = records().pushPending('rec_legacy0002');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await client.db.writeLocalUpdate(
        _collection, 'rec_legacy0002', {'number': 9},
        sync: true);
    gate.complete();
    await push;

    final between = await row('rec_legacy0002');
    expect(between![RecordMeta.synced], false);
    expect(between['number'], 9);

    await records().pushPending('rec_legacy0002');
    expect(server['rec_legacy0002']!['plain_text'], 'offline edit');
    expect(server['rec_legacy0002']!['number'], 9);
  });

  test('a cacheOnly delete of the own pending change works', () async {
    client.authStore.save('token', RecordModel({'id': 'account_a'}));
    await seedSynced('rec_owndel0001', {'plain_text': 'v0'});
    await client.db.writeLocalUpdate(
        _collection, 'rec_owndel0001', {'plain_text': 'mine'},
        sync: true, owner: 'account_a');

    await records()
        .delete('rec_owndel0001', requestPolicy: RequestPolicy.cacheOnly);
    expect((await row('rec_owndel0001'))![RecordMeta.deleted], true);
  });

  test('a cacheOnly change made during a push stays local', () async {
    await seedSynced('rec_localonly1', {'plain_text': 'v0'});
    await client.db.writeLocalUpdate(
        _collection, 'rec_localonly1', {'plain_text': 'v1'},
        sync: true);

    final gate = gates['PATCH'] = Completer<void>();
    final push = records().pushPending('rec_localonly1');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await records().update('rec_localonly1',
        body: {'plain_text': 'device only'},
        requestPolicy: RequestPolicy.cacheOnly);
    gate.complete();
    await push;

    final local = await row('rec_localonly1');
    expect(local!['plain_text'], 'device only');
    expect(local[RecordMeta.noSync], true);
    expect(server['rec_localonly1']!['plain_text'], 'v1');
  });

  test(
      'deleting a pending create while its push is in flight deletes it on '
      'the server', () async {
    final created = await records().writeLocalCreate(
        {'id': 'rec_inflight01', 'plain_text': 'new'},
        sync: true);

    final gate = gates['POST'] = Completer<void>();
    final push = records().pushPending(created.id);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    await records()
        .delete(created.id, requestPolicy: RequestPolicy.cacheAndNetwork);
    final tombstone = await row(created.id);
    expect(tombstone, isNotNull,
        reason: 'the create may reach the server: a deletion is queued');
    expect(tombstone![RecordMeta.deleted], true);

    gate.complete();
    await push;
    await records().pushPending(created.id);

    expect(server.containsKey(created.id), isFalse);
    expect(await row(created.id), isNull);
    expect(writes().map((s) => s.method), ['POST', 'DELETE']);
  });

  test('an edit during the create push keeps the uploaded file names',
      () async {
    final created = await records().writeLocalCreate(
      {'id': 'rec_upload0001', 'plain_text': 'v1'},
      files: [
        ('file_multi', 'photo.jpg', Uint8List.fromList([1, 2, 3]))
      ],
      sync: true,
    );

    final gate = gates['POST'] = Completer<void>();
    final push = records().pushPending(created.id);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await records()
        .writeLocalUpdate(created.id, {'plain_text': 'v2'}, sync: true);
    gate.complete();
    await push;

    final afterCreate = await row(created.id);
    final serverName = (server[created.id]!['file_multi'] as List).single;
    expect(afterCreate!['file_multi'], [serverName]);
    expect(afterCreate[RecordMeta.pendingFields], ['plain_text']);
    expect(afterCreate[RecordMeta.pendingFiles], isNull);
    expect(
        await client.db
            .getFile(created.id, serverName as String)
            .getSingleOrNull(),
        isNotNull);

    await records().pushPending(created.id);
    final patch = writes().last;
    expect(patch.method, 'PATCH');
    expect(patch.body, {'plain_text': 'v2'});
    expect(patch.files, isEmpty);
    expect(server[created.id]!['file_multi'], [serverName]);
    expect((await row(created.id))![RecordMeta.synced], true);
  });

  test('a file attached during an update push is still uploaded', () async {
    await seedSynced('rec_upload0002', {'plain_text': 'v0', 'file_multi': []});
    await client.db.writeLocalUpdate(
        _collection, 'rec_upload0002', {'plain_text': 'v1'},
        sync: true);

    final gate = gates['PATCH'] = Completer<void>();
    final push = records().pushPending('rec_upload0002');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await records().writeLocalUpdate(
      'rec_upload0002',
      {},
      files: [
        ('file_multi+', 'late.png', Uint8List.fromList([9]))
      ],
      sync: true,
    );
    gate.complete();
    await push;

    final between = await row('rec_upload0002');
    expect(between![RecordMeta.synced], false);
    expect(between['file_multi'], ['late.png']);

    await records().pushPending('rec_upload0002');
    final uploads = writes().expand((s) => s.files).toList();
    expect(uploads, [('file_multi+', 'late.png')]);
    expect((server['rec_upload0002']!['file_multi'] as List).single,
        startsWith('late_'));
    expect((await row('rec_upload0002'))![RecordMeta.synced], true);
  });

  test('a deletion queued during an update push stays a deletion', () async {
    await seedSynced('rec_tombstone1', {'plain_text': 'v0'});
    await client.db.writeLocalUpdate(
        _collection, 'rec_tombstone1', {'plain_text': 'v1'},
        sync: true);

    final gate = gates['PATCH'] = Completer<void>();
    final push = records().pushPending('rec_tombstone1');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await client.db.writeLocalDelete(_collection, 'rec_tombstone1', sync: true);
    gate.complete();
    await push;

    final between = await row('rec_tombstone1');
    expect(between![RecordMeta.deleted], true);

    await records().pushPending('rec_tombstone1');
    expect(server.containsKey('rec_tombstone1'), isFalse);
    expect(await row('rec_tombstone1'), isNull);
  });

  test('pushes of one record run one at a time and upload a file once',
      () async {
    await seedSynced('rec_serial0001', {'plain_text': 'v0', 'file_multi': []});

    final gate = gates['PATCH'] = Completer<void>();
    await records().update(
      'rec_serial0001',
      body: {'plain_text': 'v1'},
      files: [
        http.MultipartFile.fromBytes('file_multi+', [1], filename: 'b.jpg')
      ],
      requestPolicy: RequestPolicy.cacheFirst,
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await records().update('rec_serial0001',
        body: {'plain_text': 'v2'}, requestPolicy: RequestPolicy.cacheFirst);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(writes().length, 1, reason: 'the second push waits for the first');
    gate.complete();
    await records().pushPending('rec_serial0001');

    final uploads = writes().expand((s) => s.files).toList();
    expect(uploads, [('file_multi+', 'b.jpg')]);
    expect(server['rec_serial0001']!['plain_text'], 'v2');
    expect((server['rec_serial0001']!['file_multi'] as List).length, 1);
    expect((await row('rec_serial0001'))![RecordMeta.synced], true);
  });

  test('a rejection does not count against an edit made during the push',
      () async {
    await seedSynced('rec_reject0001', {'plain_text': 'v0'});
    await client.db.writeLocalUpdate(
        _collection, 'rec_reject0001', {'plain_text': 'bad'},
        sync: true);

    final gate = gates['PATCH'] = Completer<void>();
    failures['PATCH'] = 400;
    final push = records().pushPending('rec_reject0001');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await client.db.writeLocalUpdate(
        _collection, 'rec_reject0001', {'plain_text': 'good'},
        sync: true);
    gate.complete();
    expect(await push, PushOutcome.rejected);

    final between = await row('rec_reject0001');
    expect(between![RecordMeta.syncError], isNull,
        reason: 'localSyncRetryCount is 1, but the new edit was never sent');

    expect(await records().pushPending('rec_reject0001'), PushOutcome.synced);
    expect(server['rec_reject0001']!['plain_text'], 'good');
  });

  test('pending edits from before field tracking still sync whole', () async {
    await seedSynced('rec_legacy0001', {'plain_text': 'v0', 'number': 0});
    // A 0.6.x pending update: no pendingFields.
    final legacy = {
      ...(await row('rec_legacy0001'))!,
      'plain_text': 'offline edit',
      RecordMeta.synced: false,
      RecordMeta.isNew: false,
      RecordMeta.deleted: false,
    };
    await client.db.$create(_collection, legacy, validate: false);

    await client.db.writeLocalUpdate(
        _collection, 'rec_legacy0001', {'number': 5},
        sync: true);
    await records().pushPending('rec_legacy0001');

    expect(server['rec_legacy0001']!['plain_text'], 'offline edit');
    expect(server['rec_legacy0001']!['number'], 5);
  });

  test('a batch update of a pending create pushes the create first', () async {
    await records().writeLocalCreate(
        {'id': 'rec_batch00001', 'plain_text': 'v1'},
        sync: true);

    final batch = client.$createBatch();
    batch
        .collection(_collection)
        .update('rec_batch00001', body: {'plain_text': 'v2'});
    final results =
        await batch.send(requestPolicy: RequestPolicy.cacheAndNetwork);

    expect(results.single.isSuccess, isTrue);
    expect(writes().map((s) => s.path),
        ['/api/collections/$_collection/records', '/api/batch']);
    expect(server['rec_batch00001']!['plain_text'], 'v2');
    expect((await row('rec_batch00001'))![RecordMeta.synced], true);
  });

  test('local writes to a change queued by another account are refused',
      () async {
    await seedSynced('rec_owner00001', {'plain_text': 'v0'});
    await client.db.writeLocalUpdate(
        _collection, 'rec_owner00001', {'plain_text': 'by a'},
        sync: true, owner: 'account_a');

    expect(
      () => client.db.writeLocalUpdate(
          _collection, 'rec_owner00001', {'plain_text': 'by b'},
          sync: true, owner: 'account_b'),
      throwsStateError,
    );
    expect(
      () => client.db.writeLocalDelete(_collection, 'rec_owner00001',
          sync: true, owner: 'account_b'),
      throwsStateError,
    );
    final kept = await client.db.rowById(_collection, 'rec_owner00001');
    expect(kept!['plain_text'], 'by a');
    expect(kept[RecordMeta.pendingOwner], 'account_a');
  });
}
