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

/// Applies a request body like PocketBase: plain keys first, then
/// modifiers; `n+`/`n-` add and subtract, multi-value fields keep unique
/// values (`f+` appends, `+f` prepends, `f-` removes).
void _pbApply(Map<String, dynamic> target, Map<String, dynamic> body) {
  final keys = body.keys.toList()..sort((a, b) => a.length.compareTo(b.length));
  for (final key in keys) {
    final name = key.replaceAll(RegExp(r'^\+|[+-]$'), '');
    final value = body[key];
    if (name == key) {
      target[key] = value;
      continue;
    }
    final current = target[name];
    if (name == 'number') {
      final a = (current as num?) ?? 0;
      target[name] = key.endsWith('-') ? a - (value as num) : a + value;
      continue;
    }
    final list = [...(current as List? ?? const [])];
    final values = value is List ? value : [value];
    if (key.endsWith('-')) {
      list.removeWhere(values.contains);
    } else if (key.startsWith('+')) {
      list.insertAll(0, [
        for (final v in values)
          if (!list.contains(v)) v
      ]);
    } else {
      for (final v in values) {
        if (!list.contains(v)) list.add(v);
      }
    }
    target[name] = list;
  }
}

/// Sync of modifier edits (`n+`, `tags+`, `tags-`, `+tags`) as deltas, so
/// concurrent changes of the same field on other devices survive.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late $PocketBase client;
  late Map<String, Map<String, dynamic>> server;
  late List<_Sent> sent;

  /// When set, the next request of that method waits for the completer.
  late Map<String, Completer<void>> gates;

  var fileCounter = 0;
  var clock = 0;

  String nextUpdated() =>
      '2026-11-05 10:00:${(clock++ % 60).toString().padLeft(2, '0')}.000Z';

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
      } else if (payload is String) {
        body = jsonDecode(payload);
      }
      for (final f in multipart.files as List<http.MultipartFile>) {
        files.add((f.field, f.filename));
      }
    }
    return _Sent(request.method, request.url.path, body, files);
  }

  /// Applies uploads like PocketBase: generated names, appended.
  void applyFiles(Map<String, dynamic> target, _Sent request) {
    for (final (field, filename) in request.files) {
      final base = field.replaceAll(RegExp(r'[+-]'), '');
      final dot = filename!.lastIndexOf('.');
      final name = '${filename.substring(0, dot)}_gen${fileCounter++}'
          '${filename.substring(dot)}';
      target[base] = [...(target[base] as List? ?? const []), name];
    }
  }

  Map<String, dynamic> patch(String id, Map<String, dynamic> body,
      [_Sent? request]) {
    final next = {...server[id]!};
    _pbApply(next, body);
    if (request != null) applyFiles(next, request);
    next['updated'] = nextUpdated();
    return server[id] = next;
  }

  Future<http.Response> handle(http.BaseRequest raw) async {
    final request = await read(raw);
    sent.add(request);
    final gate = gates.remove(request.method);
    if (gate != null) await gate.future;

    if (request.path == '/api/batch') {
      final results = <Map<String, dynamic>>[];
      for (final r in request.body['requests'] as List) {
        final id = Uri.parse(r['url'] as String).pathSegments.last;
        final body = (r['body'] as Map).cast<String, dynamic>();
        results.add({'status': 200, 'body': patch(id, body)});
      }
      return http.Response(jsonEncode(results), 200);
    }
    final segments = request.path.split('/');
    final records = segments.indexOf('records');
    if (records == -1) return http.Response('{}', 404);
    final id = segments.length > records + 1 ? segments[records + 1] : null;
    final existing = server[id];
    if (existing == null) return http.Response('{"status":404}', 404);
    switch (request.method) {
      case 'PATCH':
        return http.Response(
            jsonEncode(patch(id!, request.body, request)), 200);
      case 'GET':
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

  /// Another device changes the server copy.
  void otherDevice(String id, Map<String, dynamic> body) => patch(id, body);

  Future<Map<String, dynamic>?> row(String id) =>
      client.db.rowById(_collection, id);

  Future<void> queue(String id, Map<String, dynamic> body,
          {List<(String, String?, Uint8List)> files = const []}) =>
      records().writeLocalUpdate(id, body, files: files, sync: true);

  List<_Sent> writes() => sent.where((s) => s.method != 'GET').toList();

  test('a queued increment adds to the server value', () async {
    await seedSynced('rec_delta00001', {'number': 10});
    await queue('rec_delta00001', {'number+': 1});
    otherDevice('rec_delta00001', {'number+': 5});

    await records().pushPending('rec_delta00001');

    expect(writes().single.body, {'number+': 1});
    expect(server['rec_delta00001']!['number'], 16);
    final cached = (await row('rec_delta00001'))!;
    expect(cached['number'], 16);
    expect(cached[RecordMeta.synced], isTrue);
  });

  test('a queued decrement is sent as number-', () async {
    await seedSynced('rec_delta00002', {'number': 10});
    await queue('rec_delta00002', {'number-': 3});
    otherDevice('rec_delta00002', {'number+': 5});

    await records().pushPending('rec_delta00002');

    expect(writes().single.body, {'number-': 3});
    expect(server['rec_delta00002']!['number'], 12);
  });

  test('a queued append keeps another device\'s append', () async {
    await seedSynced('rec_delta00003', {
      'relation_multi': ['a']
    });
    await queue('rec_delta00003', {
      'relation_multi+': ['mine']
    });
    otherDevice('rec_delta00003', {
      'relation_multi+': ['theirs']
    });

    await records().pushPending('rec_delta00003');

    expect(writes().single.body, {
      'relation_multi+': ['mine']
    });
    expect(
        server['rec_delta00003']!['relation_multi'], ['a', 'theirs', 'mine']);
    expect((await row('rec_delta00003'))!['relation_multi'],
        ['a', 'theirs', 'mine']);
  });

  test('a queued prepend is sent as +field', () async {
    await seedSynced('rec_delta00004', {
      'relation_multi': ['a']
    });
    await queue('rec_delta00004', {
      '+relation_multi': ['p']
    });
    otherDevice('rec_delta00004', {
      'relation_multi+': ['theirs']
    });

    await records().pushPending('rec_delta00004');

    expect(writes().single.body, {
      '+relation_multi': ['p']
    });
    expect(server['rec_delta00004']!['relation_multi'], ['p', 'a', 'theirs']);
  });

  test('a queued removal keeps another device\'s addition', () async {
    await seedSynced('rec_delta00005', {
      'relation_multi': ['a', 'b']
    });
    await queue('rec_delta00005', {
      'relation_multi-': ['a']
    });
    otherDevice('rec_delta00005', {
      'relation_multi+': ['theirs']
    });

    await records().pushPending('rec_delta00005');

    expect(writes().single.body, {
      'relation_multi-': ['a']
    });
    expect(server['rec_delta00005']!['relation_multi'], ['b', 'theirs']);
  });

  test('a queued file removal keeps files another device uploaded', () async {
    await seedSynced('rec_delta00006', {
      'file_multi': ['one_s1.jpg', 'two_s2.jpg']
    });
    await queue(
      'rec_delta00006',
      {
        'file_multi-': ['one_s1.jpg']
      },
      files: [
        ('file_multi+', 'mine.jpg', Uint8List.fromList([1]))
      ],
    );
    otherDevice('rec_delta00006', {
      'file_multi+': ['theirs_s3.jpg']
    });

    await records().pushPending('rec_delta00006');

    final request = writes().single;
    expect(request.body, {
      'file_multi-': ['one_s1.jpg']
    });
    expect(request.files.single.$1, 'file_multi+');
    final files = server['rec_delta00006']!['file_multi'] as List;
    expect(files.take(2), ['two_s2.jpg', 'theirs_s3.jpg']);
    expect(files.last, startsWith('mine_gen'));
    final cached = (await row('rec_delta00006'))!;
    expect(cached['file_multi'], files);
    expect(cached[RecordMeta.synced], isTrue);
  });

  test('an online cacheFirst update sends the increment', () async {
    await seedSynced('rec_delta00007', {'number': 10});
    otherDevice('rec_delta00007', {'number+': 5});

    await records().update('rec_delta00007',
        body: {'number+': 1}, requestPolicy: RequestPolicy.cacheFirst);
    await records().pushPending('rec_delta00007');

    expect(writes().single.body, {'number+': 1});
    expect(server['rec_delta00007']!['number'], 16);
    expect((await row('rec_delta00007'))!['number'], 16);
  });

  test('an increment made during the push is sent once, after it', () async {
    await seedSynced('rec_delta00008', {'number': 10});
    await queue('rec_delta00008', {'number+': 1});

    final gate = gates['PATCH'] = Completer<void>();
    final push = records().pushPending('rec_delta00008');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await queue('rec_delta00008', {'number+': 2});
    otherDevice('rec_delta00008', {'number+': 10});
    gate.complete();
    await push;

    final between = (await row('rec_delta00008'))!;
    expect(server['rec_delta00008']!['number'], 21);
    expect(between[RecordMeta.synced], isFalse);
    expect(between['number'], 23, reason: 'server value + the unsent +2');
    expect(between[RecordMeta.pendingBase], {'number': 21});

    await records().pushPending('rec_delta00008');
    expect(writes().map((w) => w.body), [
      {'number+': 1},
      {'number+': 2},
    ]);
    expect(server['rec_delta00008']!['number'], 23);
    expect((await row('rec_delta00008'))![RecordMeta.synced], isTrue);
  });

  test('a set in the field\'s history sends the absolute value', () async {
    await seedSynced('rec_delta00009', {'number': 10});
    await seedSynced('rec_delta00010', {'number': 10});
    await queue('rec_delta00009', {'number': 5});
    await queue('rec_delta00009', {'number+': 1});
    await queue('rec_delta00010', {'number+': 1});
    await queue('rec_delta00010', {'number': 7});

    await records().pushPending('rec_delta00009');
    await records().pushPending('rec_delta00010');

    expect(writes().map((w) => w.body), [
      {'number': 6},
      {'number': 7},
    ]);
  });

  test('a pending row without a base sends the absolute value', () async {
    // Queued before bases were tracked (0.7.0 without pendingBase).
    await seedSynced('rec_delta00011', {'number': 10});
    await client.db.$create(
        _collection,
        {
          ...(await row('rec_delta00011'))!,
          'number': 11,
          RecordMeta.synced: false,
          RecordMeta.isNew: false,
          RecordMeta.deleted: false,
          RecordMeta.pendingFields: ['number'],
          RecordMeta.pendingRev: 1,
        },
        validate: false);
    await queue('rec_delta00011', {'number+': 1});

    await records().pushPending('rec_delta00011');

    expect(writes().single.body, {'number': 12});
  });

  test('the base survives realtime merges and repeated edits', () async {
    await seedSynced('rec_delta00012', {'number': 10, 'plain_text': 'v0'});
    await queue('rec_delta00012', {'number+': 1});
    await queue('rec_delta00012', {'number+': 2, 'plain_text': 'mine'});
    otherDevice('rec_delta00012', {'number+': 5, 'plain_text': 'theirs'});
    await records().onEvent(RecordSubscriptionEvent(
        action: 'update',
        record: RecordModel.fromJson(server['rec_delta00012']!)));

    final pending = (await row('rec_delta00012'))!;
    expect(pending['number'], 13, reason: 'local values win until synced');
    expect(pending[RecordMeta.pendingBase], {'number': 10, 'plain_text': 'v0'});
    expect(pending[RecordMeta.baseUpdated], '2026-11-04 10:00:00.000Z');
    expect(pending[RecordMeta.pendingDeltas], {'number': 'number'});

    await records().pushPending('rec_delta00012');
    expect(writes().single.body, {'number+': 3, 'plain_text': 'mine'});
    expect(server['rec_delta00012']!['number'], 18);
  });

  test('an online modifier keeps a queued delta of the same field', () async {
    await seedSynced('rec_delta00013', {'number': 10});
    await queue('rec_delta00013', {'number+': 1});

    await records().update('rec_delta00013',
        body: {'number+': 2}, requestPolicy: RequestPolicy.networkFirst);

    expect(server['rec_delta00013']!['number'], 12);
    final between = (await row('rec_delta00013'))!;
    expect(between['number'], 13);
    expect(between[RecordMeta.pendingFields], ['number']);

    await records().pushPending('rec_delta00013');
    expect(writes().last.body, {'number+': 1});
    expect(server['rec_delta00013']!['number'], 13);
  });

  test('an online plain set still supersedes a queued delta', () async {
    await seedSynced('rec_delta00014', {'number': 10});
    await queue('rec_delta00014', {'number+': 1});

    await records().update('rec_delta00014',
        body: {'number': 50}, requestPolicy: RequestPolicy.networkFirst);

    final cached = (await row('rec_delta00014'))!;
    expect(cached['number'], 50);
    expect(cached[RecordMeta.synced], isTrue);
  });

  test('an offline batch update with modifiers syncs as deltas', () async {
    await seedSynced('rec_delta00015', {
      'number': 10,
      'relation_multi': ['a']
    });
    client.connectivity.setConnectivityStatus(false);
    final batch = client.$createBatch();
    batch.collection(_collection).update('rec_delta00015', body: {
      'number+': 2,
      'relation_multi+': ['mine'],
    });
    await batch.send(requestPolicy: RequestPolicy.cacheAndNetwork);
    expect(writes(), isEmpty);
    otherDevice('rec_delta00015', {
      'number+': 5,
      'relation_multi+': ['theirs'],
    });

    client.connectivity.setConnectivityStatus(true);
    await records().pushPending('rec_delta00015');

    expect(writes().single.body, {
      'number+': 2,
      'relation_multi+': ['mine'],
    });
    expect(server['rec_delta00015']!['number'], 17);
    expect(
        server['rec_delta00015']!['relation_multi'], ['a', 'theirs', 'mine']);
  });

  test('a deletion keeps the base on the tombstone', () async {
    await seedSynced('rec_delta00016', {'number': 10});
    await seedSynced('rec_delta00017', {'number': 10});
    await queue('rec_delta00016', {'number+': 1});
    await records().writeLocalDelete('rec_delta00016', sync: true);
    await records().writeLocalDelete('rec_delta00017', sync: true);

    final edited = (await client.db
            .$query(_collection,
                filter: "id = 'rec_delta00016'", includeDeleted: true)
            .get())
        .single;
    final plain = (await client.db
            .$query(_collection,
                filter: "id = 'rec_delta00017'", includeDeleted: true)
            .get())
        .single;
    expect(edited[RecordMeta.pendingBase], {'number': 10});
    expect(edited[RecordMeta.baseUpdated], '2026-11-04 10:00:00.000Z');
    expect(edited[RecordMeta.pendingDeltas], isNull);
    expect(plain[RecordMeta.baseUpdated], '2026-11-04 10:00:00.000Z');
  });
}
