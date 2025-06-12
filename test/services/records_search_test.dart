import 'dart:convert';
import 'dart:io' as io;
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:pocketbase_drift/pocketbase_drift.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_data/collections.json.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  io.HttpOverrides.global = null;

  const username = 'test@admin.com';
  const password = 'Password123';
  const url = 'http://127.0.0.1:8090';

  late $PocketBase client;
  late $RecordService todoService;
  late $RecordService ultimateService;

  final collections = [...offlineCollections]
      .map((e) => CollectionModel.fromJson(jsonDecode(jsonEncode(e))))
      .toList();

  setUpAll(() async {
    hierarchicalLoggingEnabled = true;
    Logger.root.level = Level.ALL;
    Logger.root.onRecord
        // ignore: avoid_print
        .listen((record) => print('${record.level.name}: ${record.message}'));

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('dev.fluttercommunity.plus/connectivity'),
            (MethodCall methodCall) async => ['wifi']);

    SharedPreferences.setMockInitialValues({});
    client = $PocketBase.database(
      url,
      authStore: $AuthStore(await SharedPreferences.getInstance(), 'pb_auth'),
      connection: DatabaseConnection(NativeDatabase.memory()),
      inMemory: true,
    );
    client.logging = true;

    await client.collection('_superusers').authWithPassword(username, password);
    await client.db.setSchema(collections.map((e) => e.toJson()).toList());
    todoService = await client.$collection('todo');
    ultimateService = await client.$collection('ultimate');
  });

  group('Records Full-Text Search', () {
    // Clean up all records after each test to ensure isolation
    tearDown(() async {
      await client.db.deleteAll(todoService.service);
      await client.db.deleteAll(ultimateService.service);
    });

    test('search within a specific collection', () async {
      // 1. Create records with distinct searchable text
      await todoService
          .create(body: {'name': 'A fast and reactive database for Flutter'});
      await todoService
          .create(body: {'name': 'Learning about PocketBase and Drift'});
      await todoService
          .create(body: {'name': 'This is a test without special keywords'});

      // 2. Search for a specific term
      var results = await todoService.search('Flutter').get();
      expect(results.length, 1);
      expect(results.first.data['name'],
          'A fast and reactive database for Flutter');

      // 3. Search for another term (case-insensitive)
      results = await todoService.search('pocketbase').get();
      expect(results.length, 1);
      expect(results.first.data['name'], 'Learning about PocketBase and Drift');

      // 4. Search for multiple terms
      results = await todoService.search('Drift PocketBase').get();
      expect(results.length, 1,
          reason: "FTS5 should match documents containing both terms.");
      expect(results.first.data['name'], 'Learning about PocketBase and Drift');

      // 5. Search for a term that doesn't exist
      results = await todoService.search('nonexistentterm').get();
      expect(results, isEmpty);
    });

    test('global search across all collections', () async {
      // 1. Create records in different collections with a common keyword
      await todoService
          .create(body: {'name': 'Building a mobile app with offline sync'});
      await ultimateService
          .create(body: {'plain_text': 'This is a test for a mobile device'});
      await ultimateService
          .create(body: {'plain_text': 'This is a test for a desktop device'});

      // 2. Perform a global search for the common keyword
      final results = await client.search('mobile').get();

      // 3. Assert that records from both collections are found
      expect(results.length, 2);
      expect(
          results.any((r) =>
              r.service == todoService.service &&
              r.data['name'].contains('mobile')),
          isTrue);
      expect(
          results.any((r) =>
              r.service == ultimateService.service &&
              r.data['plain_text'].contains('mobile')),
          isTrue);
    });

    test('FTS index is updated correctly on record UPDATE', () async {
      // 1. Create an initial record
      final item = await todoService
          .create(body: {'name': 'Initial searchable content'});

      // 2. Verify initial search works
      var results = await todoService.search('Initial').get();
      expect(results.length, 1);
      expect(results.first.id, item.id);

      // 3. Update the record
      await todoService
          .update(item.id, body: {'name': 'Updated content is now here'});

      // 4. Verify search for old content fails
      results = await todoService.search('Initial').get();
      expect(results, isEmpty,
          reason: "Search should not find the old content after update.");

      // 5. Verify search for new content succeeds
      results = await todoService.search('Updated').get();
      expect(results.length, 1,
          reason: "Search should find the new content after update.");
      expect(results.first.id, item.id);
    });

    test('FTS index is updated correctly on record DELETE', () async {
      // 1. Create a record
      final item = await todoService
          .create(body: {'name': 'This content will be deleted'});

      // 2. Verify it's searchable
      var results = await todoService.search('deleted').get();
      expect(results.length, 1);

      // 3. Delete the record
      await todoService.delete(item.id);

      // 4. Verify it's no longer searchable
      results = await todoService.search('deleted').get();
      expect(results, isEmpty,
          reason:
              "Search should not find the record after it has been deleted.");
    });
  });
}
