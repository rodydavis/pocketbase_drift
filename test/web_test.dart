import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:pocketbase_drift/pocketbase_drift.dart';

import 'test_data/collections.json.dart';

void main() {
  group('Web Platform Support', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    late $PocketBase client;
    late $RecordService todoService;
    final collections = [...offlineCollections]
        .map((e) => CollectionModel.fromJson(jsonDecode(jsonEncode(e))))
        .toList();

    setUpAll(() async {
      // Basic logging setup for debugging in the browser console.
      hierarchicalLoggingEnabled = true;

      Logger.root.level = Level.ALL;
      Logger.root.onRecord.listen((record) {
        // ignore: avoid_print
        print('${record.level.name}: ${record.time}: ${record.message}');
      });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel('dev.fluttercommunity.plus/connectivity'),
              (MethodCall methodCall) async => ['wifi']);

      // Initialize the database client FOR WEB.
      // We don't need a real URL or auth for this test, as we're only
      // interacting with the local Wasm-based database.
      client = $PocketBase.database(
        'http://localhost', // Dummy URL
        inMemory: true, // Use an in-memory database for clean tests
      );
      client.logging = true;

      // Load the schema into the in-memory database.
      await client.db.setSchema(collections.map((e) => e.toJson()).toList());
      todoService = await client.$collection('todo');
    });

    test('can initialize database and load schema on web', () async {
      final localCollections = await client.db.$collections().get();
      expect(localCollections.length, collections.length);
      expect(localCollections.any((c) => c.name == 'todo'), isTrue);
    });

    test('can create a record in the local web database', () async {
      final recordName = 'My Web Record';
      final item = await todoService.create(
        body: {'name': recordName},
        requestPolicy: RequestPolicy.cacheOnly, // Force local DB interaction
      );

      expect(item.data['name'], recordName);
      expect(item.id, isNotEmpty);
    });

    test('can query a record from the local web database', () async {
      final recordName = 'Queryable Web Record';
      await todoService.create(
        body: {'name': recordName},
        requestPolicy: RequestPolicy.cacheOnly,
      );

      final results = await todoService.getFullList(
        filter: "name = '$recordName'",
        requestPolicy: RequestPolicy.cacheOnly,
      );

      expect(results.length, 1);
      expect(results.first.data['name'], recordName);
    });

    test('can delete a record from the local web database', () async {
      final recordName = 'Deletable Web Record';
      final item = await todoService.create(
        body: {'name': recordName},
        requestPolicy: RequestPolicy.cacheOnly,
      );

      // Verify it exists
      var results =
          await todoService.getFullList(requestPolicy: RequestPolicy.cacheOnly);
      expect(results.any((r) => r.id == item.id), isTrue);

      // Delete it
      await todoService.delete(item.id, requestPolicy: RequestPolicy.cacheOnly);

      // Verify it is marked as deleted locally
      final deletedItem = await todoService.getOne(item.id,
          requestPolicy: RequestPolicy.cacheOnly);
      expect(deletedItem, isNotNull);
      expect(deletedItem.data['deleted'], isTrue,
          reason: "The record should be marked as deleted locally.");
    });
  });
}
