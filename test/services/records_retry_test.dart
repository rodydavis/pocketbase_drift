import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:pocketbase_drift/pocketbase_drift.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_data/collections.json.dart';

class MockHttpClient extends http.BaseClient {
  final Future<http.Response> Function(http.BaseRequest request) handler;
  MockHttpClient(this.handler);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await handler(request);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      contentLength: response.contentLength,
      request: request,
      headers: response.headers,
      reasonPhrase: response.reasonPhrase,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  io.HttpOverrides.global = null;

  group('Record Retry Tests', () {
    late $PocketBase client;
    final collections = [...offlineCollections]
        .map((e) => CollectionModel.fromJson(jsonDecode(jsonEncode(e))))
        .toList();

    setUpAll(() {
      hierarchicalLoggingEnabled = true;
      Logger.root.level = Level.ALL;
      Logger.root.onRecord.listen((record) {
        // ignore: avoid_print
        print('${record.level.name}: ${record.time}: ${record.message}');
      });
    });

    // Setup function to create client with a specific mock handler
    Future<void> setupClient({
      required Future<http.Response> Function(http.BaseRequest request)
          mockHandler,
      int maxRetries = 2,
    }) async {
      SharedPreferences.setMockInitialValues({});

      // Mock connectivity to always be online so retryLocal runs immediately when requested
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel('dev.fluttercommunity.plus/connectivity'),
              (MethodCall methodCall) async => ['wifi']);

      final mockClient = MockHttpClient(mockHandler);

      client = $PocketBase.database(
        'http://test-url.com',
        httpClientFactory: () => mockClient,
        localSyncRetryCount: maxRetries,
        inMemory: true,
        connection: DatabaseConnection(NativeDatabase.memory()),
      );
      client.logging = true;

      // Initialize DB schema
      await client.db.setSchema(collections.map((e) => e.toJson()).toList());
    }

    tearDown(() {
      client.close();
    });

    test('should increment retryCount on 400 Bad Request error', () async {
      await setupClient(
        mockHandler: (request) async {
          // Simulate 400 Bad Request for any creation/update
          if (request.method == 'POST' || request.method == 'PATCH') {
            return http.Response(
                '{"code": 400, "message": "Validation error", "data": {}}',
                400);
          }
          return http.Response('{}', 200);
        },
        maxRetries: 5,
      );

      final collection = client.collection('todo');

      // 1. Create a record "offline" (simulate by sticking it in DB directly)
      final recordId = 'test_record_1';
      await client.db.$create('todo', {
        'id': recordId,
        'name': 'test_name',
        'synced': false,
        'isNew': true,
        'deleted': false,
        'retryCount': 0,
      });

      // 2. Trigger retryLocal
      await (collection).retryLocal().drain();

      // 3. Verify retryCount is incremented
      final record = await client.db
          .$query('todo', filter: "id = '$recordId'")
          .getSingle();
      final retryCount = (record['retryCount'] as num?)?.toInt();
      expect(retryCount, equals(1),
          reason: "retryCount should increment to 1 after first failure");
    });

    test(
        'parks a change the server rejected localSyncRetryCount times and '
        'reports it', () async {
      var posts = 0;
      await setupClient(
        mockHandler: (request) async {
          if (request.method == 'POST' || request.method == 'PATCH') {
            posts++;
            return http.Response(
                '{"code": 400, "message": "Validation error"}', 400);
          }
          return http.Response('{}', 200);
        },
        maxRetries: 2,
      );

      final collection = client.collection('todo');
      final recordId = 'test_park_sync';
      final failures = <SyncFailure>[];
      final sub = client.syncFailures.listen(failures.add);

      await client.db.$create('todo', {
        'id': recordId,
        'name': 'test_park',
        'synced': false,
        'isNew': true,
        'retryCount': 0,
      });

      await collection.retryLocal().drain();
      var record = await client.db.rowById('todo', recordId);
      expect(record!['retryCount'], 1);
      expect(record['syncError'], isNull);
      expect(failures, isEmpty);

      await collection.retryLocal().drain();
      record = await client.db.rowById('todo', recordId);
      expect(record, isNotNull,
          reason: 'A rejected change is kept for the user, never deleted');
      expect(record!['syncError'], isA<Map>());
      expect((record['syncError'] as Map)['status'], 400);
      expect(failures.single.recordId, recordId);
      expect(failures.single.statusCode, 400);
      expect(failures.single.operation, SyncOperation.create);

      // Automatic sync skips the parked change; an explicit retry sends it.
      final before = posts;
      await collection.retryLocal().drain();
      expect(posts, before);
      await collection.retryLocal(includeFailed: true).drain();
      expect(posts, before + 1);

      await sub.cancel();
    });

    test('should NOT delete record on non-400 errors', () async {
      await setupClient(
        mockHandler: (request) async {
          // Simulate 500 Server Error
          if (request.method == 'POST') {
            return http.Response(
                '{"code": 500, "message": "Server error"}', 500);
          }
          return http.Response('{}', 200);
        },
        maxRetries: 2,
      );

      final collection = client.collection('todo');
      final recordId = 'test_keep_sync';

      await client.db.$create('todo', {
        'id': recordId,
        'name': 'test_keep',
        'synced': false,
        'isNew': true,
        'retryCount': 0,
      });

      // Run retry multiple times
      await collection.retryLocal().drain();
      await collection.retryLocal().drain();
      await collection.retryLocal().drain();

      // Verify record still exists and retryCount is NOT incremented (or at least record not deleted)
      // The implementation only increments retryCount for 400 errors.
      var record = await client.db
          .$query('todo', filter: "id = '$recordId'")
          .getSingleOrNull();
      expect(record, isNotNull);
      expect(record!['retryCount'], anyOf(isNull, 0),
          reason: "retryCount should not increment for non-400 errors");
    });

    test('a parked change keeps its file blobs until it is discarded',
        () async {
      await setupClient(
        mockHandler: (request) async {
          return http.Response(
              '{"code": 400, "message": "Validation error"}', 400);
        },
        maxRetries: 1,
      );

      final collection = client.collection('ultimate');
      final recordId = 'test_file_cleanup';
      final fileName = 'test_file.txt';

      await client.db.$create('ultimate', {
        'id': recordId,
        'plain_text': 'test_file_record',
        'file_single': fileName,
        'synced': false,
        'isNew': true,
        'retryCount': 0,
      });
      await client.db.setFile(
        recordId,
        fileName,
        Uint8List.fromList([1, 2, 3]),
      );

      await collection.retryLocal().drain();

      final record = await client.db.rowById('ultimate', recordId);
      expect(record?['syncError'], isNotNull);
      expect(await client.db.getFile(recordId, fileName).getSingleOrNull(),
          isNotNull,
          reason: 'The upload must still be possible after fixing the data');

      await client.discardPendingChange('ultimate', recordId);

      expect(await client.db.rowById('ultimate', recordId), isNull);
      expect(
          await client.db.getFile(recordId, fileName).getSingleOrNull(), isNull,
          reason: 'File blob should be deleted with the record');
    });
  });
}
