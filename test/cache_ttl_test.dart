import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase_drift/pocketbase_drift.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_data/collections.json.dart';
import 'test_server.dart';

/// Sets when the row [id] was cached; TTL maintenance expires rows by it.
Future<void> age(DataBase db, String id, DateTime cachedAt) async {
  await (db.update(db.services)..where((r) => r.id.equals(id)))
      .write(ServicesCompanion(cachedAt: Value(cachedAt)));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Suppress warnings about multiple database instances in tests
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('Cache TTL & Expiration', () {
    late $PocketBase client;
    late $RecordService todoService;

    final url = testServerUrl;
    final collections = [...offlineCollections]
        .map((e) => CollectionModel.fromJson(jsonDecode(jsonEncode(e))))
        .toList();

    setUpAll(() async {
      // Mock connectivity as online
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel('dev.fluttercommunity.plus/connectivity'),
              (MethodCall methodCall) async => ['wifi']);

      SharedPreferences.setMockInitialValues({});
    });

    setUp(() async {
      // Create a fresh in-memory database for each test
      client = $PocketBase.database(
        url,
        connection: DatabaseConnection(NativeDatabase.memory()),
        cacheTtl: const Duration(days: 60), // Default TTL
      );

      // Initialize the schema
      await client.db.setSchema(
        collections.map((e) => e.toJson()).toList(),
      );

      todoService = client.collection('todo');
    });

    tearDown(() async {
      await client.db.clearAllData();
    });

    test('runMaintenance returns zero counts when no expired data', () async {
      // Create a record (it will have current timestamp)
      await client.db.$create('todo', {
        'id': 'fresh_record',
        'name': 'Fresh Record',
        'synced': true,
        'deleted': false,
      });

      // Run maintenance with default TTL (60 days)
      final result = await client.runMaintenance();

      expect(result.deletedRecords, 0);
      expect(result.deletedResponses, 0);
      expect(result.deletedFiles, 0);
      expect(result.totalDeleted, 0);
    });

    test('cleanupExpiredRecords deletes old synced records', () async {
      final oldDate = DateTime.now().subtract(const Duration(days: 90));
      final recentDate = DateTime.now().subtract(const Duration(days: 30));

      // Create an old synced record (should be deleted)
      await client.db.$create('todo', {
        'id': 'old_synced',
        'name': 'Old Synced',
        'synced': true,
        'deleted': false,
        'updated': oldDate.toIso8601String(),
      });
      await age(client.db, 'old_synced', oldDate);

      // Create a recent synced record (should NOT be deleted)
      await client.db.$create('todo', {
        'id': 'recent_synced',
        'name': 'Recent Synced',
        'synced': true,
        'deleted': false,
        'updated': recentDate.toIso8601String(),
      });
      await age(client.db, 'recent_synced', recentDate);

      // Run maintenance with 60-day TTL
      final cutoff = DateTime.now().subtract(const Duration(days: 60));
      final deleted = await client.db.cleanupExpiredRecords(cutoffDate: cutoff);

      expect(deleted, 1);

      // Verify old record is deleted
      final oldRecord = await todoService.getOneOrNull(
        'old_synced',
        requestPolicy: RequestPolicy.cacheOnly,
      );
      expect(oldRecord, isNull);

      // Verify recent record still exists
      final recentRecord = await todoService.getOneOrNull(
        'recent_synced',
        requestPolicy: RequestPolicy.cacheOnly,
      );
      expect(recentRecord, isNotNull);
    });

    test('cleanupExpiredRecords preserves unsynced records', () async {
      final oldDate = DateTime.now().subtract(const Duration(days: 90));

      // Create an old UNSYNCED record (should NOT be deleted)
      await client.db.$create('todo', {
        'id': 'old_unsynced',
        'name': 'Old Unsynced',
        'synced': false,
        'deleted': false,
        'updated': oldDate.toIso8601String(),
      });
      await age(client.db, 'old_unsynced', oldDate);

      // Run maintenance
      final cutoff = DateTime.now().subtract(const Duration(days: 60));
      final deleted = await client.db.cleanupExpiredRecords(cutoffDate: cutoff);

      expect(deleted, 0);

      // Verify record still exists
      final record = await todoService.getOneOrNull(
        'old_unsynced',
        requestPolicy: RequestPolicy.cacheOnly,
      );
      expect(record, isNotNull);
    });

    test('cleanupExpiredRecords preserves local-only records', () async {
      final oldDate = DateTime.now().subtract(const Duration(days: 90));

      // Create an old local-only record (noSync = true)
      await client.db.$create('todo', {
        'id': 'old_local_only',
        'name': 'Old Local Only',
        'synced': true,
        'noSync': true,
        'deleted': false,
        'updated': oldDate.toIso8601String(),
      });
      await age(client.db, 'old_local_only', oldDate);

      // Run maintenance
      final cutoff = DateTime.now().subtract(const Duration(days: 60));
      final deleted = await client.db.cleanupExpiredRecords(cutoffDate: cutoff);

      expect(deleted, 0);

      // Verify record still exists
      final record = await todoService.getOneOrNull(
        'old_local_only',
        requestPolicy: RequestPolicy.cacheOnly,
      );
      expect(record, isNotNull);
    });

    test('cleanupExpiredResponses deletes old cached responses', () async {
      final oldDate = DateTime.now().subtract(const Duration(days: 90));

      // Manually insert an old cached response
      await client.db.into(client.db.cachedResponses).insert(
            CachedResponsesCompanion.insert(
              requestKey: 'old_response_key',
              responseData: '{"items": []}',
              cachedAt: Value(oldDate),
            ),
          );

      // Insert a recent cached response
      await client.db.cacheResponse('recent_response_key', '{"items": []}');

      // Run cleanup
      final cutoff = DateTime.now().subtract(const Duration(days: 60));
      final deleted =
          await client.db.cleanupExpiredResponses(cutoffDate: cutoff);

      expect(deleted, 1);

      // Verify old response is deleted
      final oldResponse = await client.db.getCachedResponse('old_response_key');
      expect(oldResponse, isNull);

      // Verify recent response still exists
      final recentResponse =
          await client.db.getCachedResponse('recent_response_key');
      expect(recentResponse, isNotNull);
    });

    test('runMaintenance uses configurable TTL', () async {
      final threeDaysAgo = DateTime.now().subtract(const Duration(days: 3));

      // Create a record from 3 days ago
      await client.db.$create('todo', {
        'id': 'three_days_old',
        'name': 'Three Days Old',
        'synced': true,
        'deleted': false,
        'updated': threeDaysAgo.toIso8601String(),
      });
      await age(client.db, 'three_days_old', threeDaysAgo);

      // Run maintenance with 60-day TTL (should NOT delete)
      var result = await client.runMaintenance();
      expect(result.deletedRecords, 0);

      // Run maintenance with 1-day TTL (SHOULD delete)
      result = await client.runMaintenance(ttl: const Duration(days: 1));
      expect(result.deletedRecords, 1);
    });

    test('runMaintenance respects client-level cacheTtl configuration',
        () async {
      // Create a client with a short TTL
      final shortTtlClient = $PocketBase.database(
        url,
        connection: DatabaseConnection(NativeDatabase.memory()),
        cacheTtl: const Duration(days: 7), // Short TTL
      );

      await shortTtlClient.db.setSchema(
        collections.map((e) => e.toJson()).toList(),
      );

      final tenDaysAgo = DateTime.now().subtract(const Duration(days: 10));

      // Create a 10-day old synced record
      await shortTtlClient.db.$create('todo', {
        'id': 'ten_days_old',
        'name': 'Ten Days Old',
        'synced': true,
        'deleted': false,
        'updated': tenDaysAgo.toIso8601String(),
      });
      await age(shortTtlClient.db, 'ten_days_old', tenDaysAgo);

      // Run maintenance with default (7-day) TTL - should delete
      final result = await shortTtlClient.runMaintenance();
      expect(result.deletedRecords, 1);

      await shortTtlClient.db.clearAllData();
    });

    test('MaintenanceResult provides correct totals', () async {
      final oldDate = DateTime.now().subtract(const Duration(days: 90));

      // Create 2 old synced records
      await client.db.$create('todo', {
        'id': 'old1',
        'name': 'Old 1',
        'synced': true,
        'deleted': false,
        'updated': oldDate.toIso8601String(),
      });
      await client.db.$create('todo', {
        'id': 'old2',
        'name': 'Old 2',
        'synced': true,
        'deleted': false,
        'updated': oldDate.toIso8601String(),
      });
      await age(client.db, 'old1', oldDate);
      await age(client.db, 'old2', oldDate);

      // Create 1 old cached response
      await client.db.into(client.db.cachedResponses).insert(
            CachedResponsesCompanion.insert(
              requestKey: 'old_key',
              responseData: '{}',
              cachedAt: Value(oldDate),
            ),
          );

      final result = await client.runMaintenance();

      expect(result.deletedRecords, 2);
      expect(result.deletedResponses, 1);
      expect(result.deletedFiles, 0); // No expired files
      expect(result.totalDeleted, 3);
    });

    test('cleanupExpiredRecords handles multiple records', () async {
      final oldDate = DateTime.now().subtract(const Duration(days: 90));

      // Create multiple old records
      await client.db.$create('todo', {
        'id': 'old_todo_1',
        'name': 'Old Todo 1',
        'synced': true,
        'deleted': false,
        'updated': oldDate.toIso8601String(),
      });

      await client.db.$create('todo', {
        'id': 'old_todo_2',
        'name': 'Old Todo 2',
        'synced': true,
        'deleted': false,
        'updated': oldDate.toIso8601String(),
      });

      await client.db.$create('todo', {
        'id': 'old_todo_3',
        'name': 'Old Todo 3',
        'synced': true,
        'deleted': false,
        'updated': oldDate.toIso8601String(),
      });
      for (final id in ['old_todo_1', 'old_todo_2', 'old_todo_3']) {
        await age(client.db, id, oldDate);
      }

      final cutoff = DateTime.now().subtract(const Duration(days: 60));
      final deleted = await client.db.cleanupExpiredRecords(cutoffDate: cutoff);

      // All old records should be deleted
      expect(deleted, 3);
    });

    test('runMaintenance does nothing when cacheTtl is null', () async {
      // Create a client with NO TTL (null)
      final noTtlClient = $PocketBase.database(
        url,
        connection: DatabaseConnection(NativeDatabase.memory()),
        cacheTtl: null, // Disabled
      );

      await noTtlClient.db.setSchema(
        collections.map((e) => e.toJson()).toList(),
      );

      final oldDate = DateTime.now().subtract(const Duration(days: 365));

      // Create a very old synced record
      await noTtlClient.db.$create('todo', {
        'id': 'ancient_record',
        'name': 'Ancient Record',
        'synced': true,
        'deleted': false,
        'updated': oldDate.toIso8601String(),
      });
      await age(noTtlClient.db, 'ancient_record', oldDate);

      // Run maintenance (should skip)
      final result = await noTtlClient.runMaintenance();

      expect(result.totalDeleted, 0);

      // Verify record still exists
      final record = await noTtlClient.collection('todo').getOneOrNull(
            'ancient_record',
            requestPolicy: RequestPolicy.cacheOnly,
          );
      expect(record, isNotNull);

      await noTtlClient.db.clearAllData();
    });

    test('expiry follows when a record was cached, not its updated time',
        () async {
      // Fetched today, last edited on the server long ago: keep it.
      await client.db.upsertServerRecords('todo', [
        {
          'id': 'fetched_today',
          'name': 'Fetched Today',
          'updated': '2020-01-01 00:00:00.000Z',
        },
      ]);
      // Cached long ago by a list fetch (no `synced` key in the payload).
      await client.db.mergeLocal('todo', [
        {'id': 'cached_long_ago', 'name': 'Cached Long Ago'},
      ]);
      await age(client.db, 'cached_long_ago',
          DateTime.now().subtract(const Duration(days: 90)));

      final result = await client.runMaintenance();

      expect(result.deletedRecords, 1);
      expect(await client.db.rowById('todo', 'fetched_today'), isNotNull);
      expect(await client.db.rowById('todo', 'cached_long_ago'), isNull);
    });
  });
}
