import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pocketbase_drift/pocketbase_drift.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../test_data/collections.json.dart';

const _kb = 1024;
const _collection = 'ultimate';
const _collectionId = 'p1fq7xv6lor6sx5';

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
    );
  }
}

/// A file upload the fake server received.
typedef _Upload = ({String field, String? filename, Uint8List bytes});

Uint8List _pattern(int size, int seed) =>
    Uint8List.fromList(List.generate(size, (i) => (i * 7 + seed) % 251));

/// The file blob cache size limit (`maxFileCacheBytes`): LRU eviction,
/// pinning of unsynced uploads, maintenance and compaction.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late $PocketBase client;
  late Map<String, Map<String, dynamic>> server;
  late List<_Upload> uploads;

  /// Size of the files the fake server sends.
  late int downloadSize;

  /// When set, the next record POST waits for it.
  Completer<void>? postGate;

  var fileCounter = 0;

  Future<http.Response> handle(http.BaseRequest request) async {
    final segments = request.url.pathSegments;
    if (segments.length > 2 && segments[1] == 'files') {
      return http.Response.bytes(Uint8List(downloadSize), 200);
    }
    final records = segments.indexOf('records');
    if (records == -1 || request.method != 'POST') {
      return http.Response('{"status":404}', 404);
    }
    final body = <String, dynamic>{};
    final created = <String, dynamic>{};
    if (request is http.Request) {
      if (request.body.isNotEmpty) body.addAll(jsonDecode(request.body));
    } else {
      // The SDK's own MultipartRequest (multi-value fields).
      final dynamic multipart = request;
      final payload = (multipart.fields as Map)['@jsonPayload'];
      if (payload is List && payload.isNotEmpty) {
        body.addAll(jsonDecode(payload.first as String));
      }
      for (final f in multipart.files as List<http.MultipartFile>) {
        final bytes = await f.finalize().toBytes();
        uploads.add((field: f.field, filename: f.filename, bytes: bytes));
        final name = f.filename!;
        final dot = name.lastIndexOf('.');
        created[f.field.replaceAll(RegExp(r'[+-]'), '')] =
            '${name.substring(0, dot)}_gen${fileCounter++}${name.substring(dot)}';
      }
    }
    final gate = postGate;
    if (gate != null) {
      postGate = null;
      await gate.future;
    }
    final id = body['id'] as String;
    server[id] = {
      'id': id,
      'collectionId': _collectionId,
      'collectionName': _collection,
      'created': '2026-11-05 10:00:00.000Z',
      'updated': '2026-11-05 10:00:00.000Z',
      ...body,
      ...created,
    };
    return http.Response(jsonEncode(server[id]), 200);
  }

  Future<$PocketBase> open({
    int? maxFileCacheBytes,
    DatabaseConnection? connection,
    Duration? cacheTtl,
  }) async {
    final c = $PocketBase.database(
      'http://mock.pb',
      connection: connection ?? DatabaseConnection(NativeDatabase.memory()),
      httpClientFactory: () => _MockClient(handle),
      maxFileCacheBytes: maxFileCacheBytes,
      cacheTtl: cacheTtl,
    );
    await c.db.setSchema(
      [...offlineCollections]
          .map((e) => jsonDecode(jsonEncode(e)) as Map<String, dynamic>)
          .toList(),
    );
    await c.syncCompleted;
    return c;
  }

  setUpAll(() {
    ConnectivityService.enableProbes = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async => ['wifi'],
    );
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    server = {};
    uploads = [];
    downloadSize = 10 * _kb;
    postGate = null;
  });

  Future<Uint8List> download(String recordId) => client.files.getFileBytes(
      recordId: recordId, recordCollectionName: 'posts', filename: 'a.jpg');

  Future<void> downloadAll(Iterable<int> ids) async {
    for (final i in ids) {
      await download('dl$i');
    }
    await client.enforceFileCacheLimit();
  }

  /// Cached blobs as `recordId/filename`.
  Future<List<String>> blobs() async => [
        for (final b in await client.db.select(client.db.blobFiles).get())
          '${b.recordId}/${b.filename}',
      ];

  Future<void> ageAllBlobs() => client.db.customUpdate(
      // lastAccess is stored as unix seconds; keep the insert order.
      'UPDATE BlobFiles SET lastAccess = lastAccess - 7200 + id');

  Future<RecordModel> createWithFile(
    String filename,
    Uint8List bytes, {
    RequestPolicy requestPolicy = RequestPolicy.cacheAndNetwork,
  }) =>
      client.collection(_collection).create(
        body: {'plain_text': filename},
        files: [
          http.MultipartFile.fromBytes('file_single', bytes,
              filename: filename),
        ],
        requestPolicy: requestPolicy,
      );

  Future<void> goOnlineAndSync() async {
    client.connectivity.setConnectivityStatus(true);
    await Future<void>.delayed(Duration.zero);
    await client.syncCompleted;
  }

  group('in-memory database', () {
    tearDown(() => client.close());

    test('downloads beyond the limit keep the cache within it, oldest out',
        () async {
      client = await open(maxFileCacheBytes: 100 * _kb);

      await downloadAll(List.generate(30, (i) => i));

      expect(await client.db.fileCacheBytes(), lessThanOrEqualTo(100 * _kb));
      final kept = await blobs();
      expect(kept, contains('dl29/a.jpg'));
      expect(kept, isNot(contains('dl0/a.jpg')));
    });

    test('a cache hit moves the file to the young end of the LRU order',
        () async {
      client = await open(maxFileCacheBytes: 100 * _kb);
      await downloadAll(List.generate(9, (i) => i));
      await ageAllBlobs();

      await download('dl0'); // cache hit
      await downloadAll([9, 10, 11]);

      final kept = await blobs();
      expect(kept, contains('dl0/a.jpg'));
      expect(kept, isNot(contains('dl1/a.jpg')));
    });

    test(
        'blobs of pending and local-only records survive eviction; the push '
        'sends the exact bytes, then the upload is evictable', () async {
      client = await open(maxFileCacheBytes: 100 * _kb);
      client.connectivity.setConnectivityStatus(false);
      final pendingBytes = _pattern(30 * _kb, 1);
      final pending = await createWithFile('p.jpg', pendingBytes);
      final local = await createWithFile('l.jpg', _pattern(30 * _kb, 2),
          requestPolicy: RequestPolicy.cacheOnly);
      await client.db.customUpdate('UPDATE BlobFiles SET lastAccess = 0');

      await downloadAll(List.generate(20, (i) => i));

      expect(await blobs(),
          containsAll(['${pending.id}/p.jpg', '${local.id}/l.jpg']));
      expect(await client.db.fileCacheBytes(), lessThanOrEqualTo(100 * _kb));

      final pushStart = DateTime.now().subtract(const Duration(seconds: 1));
      await goOnlineAndSync();

      expect(uploads, hasLength(1));
      expect(uploads.single.bytes, pendingBytes);
      final serverName = server[pending.id]!['file_single'] as String;
      final renamed =
          await client.db.getFile(pending.id, serverName).getSingle();
      expect(renamed.lastAccess!.isAfter(pushStart), isTrue);

      await client.db.evictFiles(maxBytes: 0);
      final kept = await blobs();
      expect(kept, isNot(contains('${pending.id}/$serverName')));
      expect(kept, contains('${local.id}/l.jpg'));
    });

    test(
        'the pending upload of another account survives eviction and syncs '
        'when that account logs in again', () async {
      client = await open(maxFileCacheBytes: 100 * _kb);
      client.connectivity.setConnectivityStatus(false);
      client.authStore.save('token', RecordModel({'id': 'account_a'}));
      final bytes = _pattern(20 * _kb, 3);
      final pending = await createWithFile('a.jpg', bytes);
      client.authStore.save('token', RecordModel({'id': 'account_b'}));
      await client.db.customUpdate('UPDATE BlobFiles SET lastAccess = 0');

      await downloadAll(List.generate(20, (i) => i));
      expect(await blobs(), contains('${pending.id}/a.jpg'));

      client.connectivity.setConnectivityStatus(true);
      client.authStore.save('token', RecordModel({'id': 'account_a'}));
      await Future<void>.delayed(Duration.zero);
      await client.syncCompleted;

      expect(uploads.single.bytes, bytes);
    });

    test('a download larger than the limit is returned but not cached',
        () async {
      client = await open(maxFileCacheBytes: 50 * _kb);
      downloadSize = 60 * _kb;

      expect((await download('big')).length, 60 * _kb);
      await client.enforceFileCacheLimit();
      expect(await blobs(), isEmpty);
    });

    test('an unsynced upload larger than the limit is kept', () async {
      client = await open(maxFileCacheBytes: 50 * _kb);
      client.connectivity.setConnectivityStatus(false);
      final pending = await createWithFile('big.jpg', _pattern(60 * _kb, 4));
      await client.enforceFileCacheLimit();

      expect(await blobs(), ['${pending.id}/big.jpg']);
    });

    test(
        'when unsynced uploads alone exceed the limit, the cache returns '
        'within it after they sync', () async {
      client = await open(maxFileCacheBytes: 100 * _kb);
      client.connectivity.setConnectivityStatus(false);
      for (var i = 0; i < 3; i++) {
        await createWithFile('p$i.jpg', _pattern(40 * _kb, i));
      }
      await downloadAll(List.generate(5, (i) => i));
      // Only the pinned 120 KB remain.
      expect(await client.db.fileCacheBytes(), 120 * _kb);

      await goOnlineAndSync();
      await client.enforceFileCacheLimit();

      expect(uploads, hasLength(3));
      expect(await client.db.fileCacheBytes(), lessThanOrEqualTo(100 * _kb));
    });

    test('runMaintenance applies the limit when cacheTtl is null', () async {
      client = await open(maxFileCacheBytes: 100 * _kb);
      for (var i = 0; i < 20; i++) {
        // Direct writes: no eviction runs.
        await client.db.setFile('r$i', 'a.jpg', Uint8List(10 * _kb));
      }

      final result = await client.runMaintenance();

      expect(result.evictedFiles, 11);
      expect(result.evictedBytes, 110 * _kb);
      expect(result.deletedFiles, 0);
      expect(result.totalDeleted, 11);
      expect(await client.db.fileCacheBytes(), 90 * _kb);
    });

    test('maxFileCacheBytes: null keeps every file', () async {
      client = await open();
      expect(client.maxFileCacheBytes, isNull);

      await downloadAll(List.generate(30, (i) => i));
      final result = await client.runMaintenance();

      expect(await blobs(), hasLength(30));
      expect(result.evictedFiles, 0);
    });

    test('the default limit is 128 MB', () {
      expect($PocketBase.defaultMaxFileCacheBytes, 128 * 1024 * 1024);
    });

    test('eviction while a push is in flight keeps the upload intact',
        () async {
      client = await open(maxFileCacheBytes: 100 * _kb);
      client.connectivity.setConnectivityStatus(false);
      final bytes = _pattern(30 * _kb, 5);
      final pending = await createWithFile('p.jpg', bytes);
      final gate = postGate = Completer<void>();

      client.connectivity.setConnectivityStatus(true);
      await Future<void>.delayed(Duration.zero);
      final push = client.syncCompleted;
      await downloadAll(List.generate(30, (i) => i));
      gate.complete();
      await push;

      expect(uploads.single.bytes, bytes);
      final row = await client.db.rowById(_collection, pending.id);
      expect(RecordMeta.isPending(row!), isFalse);
      final serverName = server[pending.id]!['file_single'] as String;
      expect((await client.db.getFile(pending.id, serverName).getSingle()).data,
          bytes);
    });
  });

  group('file database', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('pbd_blob_cache');
    });

    tearDown(() async {
      client.close();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await dir.delete(recursive: true);
    });

    int fileSize(String path) => File(path).lengthSync();

    Future<int> autoVacuum() async =>
        (await client.db.customSelect('PRAGMA auto_vacuum').getSingle())
            .data
            .values
            .first as int;

    test('a new database returns the pages of evicted files on maintenance',
        () async {
      final path = '${dir.path}/new.db';
      client = await open(
        maxFileCacheBytes: 1024 * _kb,
        // Like connection/native.dart: background isolate, WAL set up
        // before the schema is created.
        connection: DatabaseConnection(NativeDatabase.createInBackground(
          File(path),
          setup: (db) => db.execute('PRAGMA journal_mode = WAL;'),
        )),
      );
      expect(await autoVacuum(), 2);
      for (var i = 0; i < 100; i++) {
        await client.db.setFile('r$i', 'a.jpg', _pattern(64 * _kb, i));
      }
      await client.db.customStatement('PRAGMA wal_checkpoint(TRUNCATE)');
      final before = fileSize(path);

      final result = await client.runMaintenance();

      expect(result.evictedFiles, greaterThan(80));
      expect(fileSize(path), lessThan(before ~/ 4));
    });

    test(
        'a database without incremental auto-vacuum shrinks only with '
        'compact(full: true)', () async {
      final path = '${dir.path}/old.db';
      // Databases created by earlier releases use auto_vacuum NONE.
      final created = DataBase(DatabaseConnection(NativeDatabase(File(path))));
      await created.customSelect('SELECT 1').get();
      await created.close();
      sqlite.sqlite3.open(path)
        ..execute('PRAGMA auto_vacuum = NONE; VACUUM;')
        ..close();
      client = await open(
        maxFileCacheBytes: 1024 * _kb,
        connection: DatabaseConnection(NativeDatabase(File(path))),
      );
      expect(await autoVacuum(), 0);
      for (var i = 0; i < 100; i++) {
        await client.db.setFile('r$i', 'a.jpg', _pattern(64 * _kb, i));
      }
      await client.runMaintenance();
      final afterMaintenance = fileSize(path);
      expect(await client.db.compact(), 0);

      final released = await client.db.compact(full: true);

      expect(released, greaterThan(0));
      expect(fileSize(path), lessThan(afterMaintenance ~/ 4));
      expect(await autoVacuum(), 2);
    });
  });
}
