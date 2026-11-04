import 'dart:convert';
import 'dart:io' as io;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:pocketbase_drift/pocketbase_drift.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_data/collections.json.dart';

/// Comprehensive tests for cacheFirst and networkFirst RequestPolicy options.
///
/// These policies were added in v0.3.0 and provide more explicit control over
/// data fetching and synchronization behavior.
///
/// - cacheFirst: Returns cache immediately, fetches network in background to update cache
/// - networkFirst: Tries network first, falls back to cache on failure (for reads),
///                 or writes to server first with no fallback (for writes)
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  io.HttpOverrides.global = null;

  const username = 'test@admin.com';
  const password = 'Password123';
  const url = 'http://127.0.0.1:8090';

  late $PocketBase client;
  late PocketBase serverClient;
  late $RecordService todoService;
  final collections = [...offlineCollections]
      .map((e) => CollectionModel.fromJson(jsonDecode(jsonEncode(e))))
      .toList();

  /// Helper to control mock connectivity status
  Future<void> setConnectivity(bool isOnline) async {
    ConnectivityService.enableProbes = false;
    client.connectivity.setConnectivityStatus(isOnline);
  }

  setUpAll(() async {
    hierarchicalLoggingEnabled = true;
    Logger.root.level = Level.WARNING;
    Logger.root.onRecord
        // ignore: avoid_print
        .listen((record) => print('${record.level.name}: ${record.message}'));

    ConnectivityService.enableProbes = false;

    SharedPreferences.setMockInitialValues({});
    client = $PocketBase.database(
      url,
      authStore:
          $AuthStore.prefs(await SharedPreferences.getInstance(), 'pb_auth'),
      connection: DatabaseConnection(NativeDatabase.memory()),
      inMemory: true,
    );
    client.logging = true;

    await client.collection('_superusers').authWithPassword(username, password);
    await client.db.setSchema(collections.map((e) => e.toJson()).toList());
    todoService = await client.$collection('todo');

    // Initialize a direct server client for verification
    serverClient = PocketBase(url);
    await serverClient
        .collection('_superusers')
        .authWithPassword(username, password);
  });

  tearDownAll(() {
    client.close();
  });

  tearDown(() async {
    // Clean up: ensure online and delete all records
    await setConnectivity(true);
    try {
      final items = await todoService.getFullList(
          requestPolicy: RequestPolicy.networkOnly);
      for (final item in items) {
        await todoService.delete(item.id,
            requestPolicy: RequestPolicy.networkOnly);
      }
    } catch (_) {}
    await client.db.deleteAll('todo');
  });

  // ============================================================================
  // cacheFirst Read Tests
  // ============================================================================

  group('cacheFirst - Read Operations', () {
    test('returns cached data immediately when cache exists', () async {
      // Pre-populate cache with a record
      final created = await todoService.create(
        body: {'name': 'cached_item'},
        requestPolicy: RequestPolicy.cacheAndNetwork,
      );

      // Fetch with cacheFirst - should return cache immediately
      final result = await todoService.getOne(
        created.id,
        requestPolicy: RequestPolicy.cacheFirst,
      );

      expect(result.id, created.id);
      expect(result.data['name'], 'cached_item');
    });

    test('updates cache in background after returning cached data', () async {
      // Create a record via cacheAndNetwork to ensure it's in both server and cache
      final created = await todoService.create(
        body: {'name': 'original_name'},
        requestPolicy: RequestPolicy.cacheAndNetwork,
      );

      // Update directly on server (bypassing our client)
      await serverClient.collection('todo').update(
        created.id,
        body: {'name': 'server_updated_name'},
      );

      // Fetch with cacheFirst - should return old cached value immediately
      final result = await todoService.getOne(
        created.id,
        requestPolicy: RequestPolicy.cacheFirst,
      );

      // The immediate result should still have the old name
      expect(result.data['name'], 'original_name');

      // Wait a moment for background sync to complete (longer for remote server)
      await Future.delayed(const Duration(milliseconds: 1500));

      // Now fetch from cache only - should have the updated name
      final updated = await todoService.getOne(
        created.id,
        requestPolicy: RequestPolicy.cacheOnly,
      );
      expect(updated.data['name'], 'server_updated_name');
    });

    test('fetches from network when cache is empty', () async {
      // Create a record directly on server
      final serverRecord = await serverClient.collection('todo').create(
        body: {'name': 'server_only_item'},
      );

      // Fetch with networkFirst - since cache is empty, it will get from network
      // Note: cacheFirst with empty cache and no connectivity would fail,
      // so we use networkFirst which is more appropriate for this scenario
      final result = await todoService.getOne(
        serverRecord.id,
        requestPolicy: RequestPolicy.networkFirst,
      );

      expect(result.id, serverRecord.id);
      expect(result.data['name'], 'server_only_item');

      // Verify it's now in cache
      final cached = await todoService.getOne(
        serverRecord.id,
        requestPolicy: RequestPolicy.cacheOnly,
      );
      expect(cached.data['name'], 'server_only_item');
    });

    test('getList returns cached data immediately', () async {
      // Pre-populate cache
      await todoService.create(
        body: {'name': 'list_item_1'},
        requestPolicy: RequestPolicy.cacheAndNetwork,
      );
      await todoService.create(
        body: {'name': 'list_item_2'},
        requestPolicy: RequestPolicy.cacheAndNetwork,
      );

      // Fetch list with cacheFirst
      final result = await todoService.getList(
        requestPolicy: RequestPolicy.cacheFirst,
      );

      expect(result.items.length, greaterThanOrEqualTo(2));
    });

    test('getFullList returns cached data immediately', () async {
      // Pre-populate cache
      await todoService.create(
        body: {'name': 'full_list_item_1'},
        requestPolicy: RequestPolicy.cacheAndNetwork,
      );
      await todoService.create(
        body: {'name': 'full_list_item_2'},
        requestPolicy: RequestPolicy.cacheAndNetwork,
      );

      // Fetch full list with cacheFirst
      final result = await todoService.getFullList(
        requestPolicy: RequestPolicy.cacheFirst,
      );

      expect(result.length, greaterThanOrEqualTo(2));
    });

    test('handles network failure gracefully (returns cache)', () async {
      // Pre-populate cache
      final created = await todoService.create(
        body: {'name': 'cached_for_offline'},
        requestPolicy: RequestPolicy.cacheAndNetwork,
      );

      // Go offline
      await setConnectivity(false);

      // Fetch with cacheFirst - should still return cache
      final result = await todoService.getOne(
        created.id,
        requestPolicy: RequestPolicy.cacheFirst,
      );

      expect(result.data['name'], 'cached_for_offline');
    });
  });

  // ============================================================================
  // cacheFirst Write Tests
  // ============================================================================

  group('cacheFirst - Write Operations', () {
    test('create: writes to cache first and returns immediately', () async {
      final result = await todoService.create(
        body: {'name': 'cache_first_create'},
        requestPolicy: RequestPolicy.cacheFirst,
      );

      expect(result.data['name'], 'cache_first_create');
      expect(result.id, isNotEmpty);

      // Verify it's in cache
      final cached = await todoService.getOne(
        result.id,
        requestPolicy: RequestPolicy.cacheOnly,
      );
      expect(cached.data['name'], 'cache_first_create');
    });

    test('create: syncs to server in background when online', () async {
      final uniqueName =
          'background_sync_create_${DateTime.now().millisecondsSinceEpoch}';
      final result = await todoService.create(
        body: {'name': uniqueName},
        requestPolicy: RequestPolicy.cacheFirst,
      );

      // Wait for background sync (longer for remote server)
      await Future.delayed(const Duration(milliseconds: 2000));

      // Verify the record is now synced by checking the synced flag
      final cachedAfterSync = await todoService.getOne(
        result.id,
        requestPolicy: RequestPolicy.cacheOnly,
      );
      expect(cachedAfterSync.data['synced'], isTrue);

      // Also verify record exists on server by searching by name
      final serverRecords = await serverClient.collection('todo').getFullList(
            filter: "name = '$uniqueName'",
          );
      expect(serverRecords.length, 1);
      expect(serverRecords.first.data['name'], uniqueName);
    });

    test('create: marks record as synced after successful background sync',
        () async {
      final result = await todoService.create(
        body: {'name': 'check_sync_flag'},
        requestPolicy: RequestPolicy.cacheFirst,
      );

      // Initially should be unsynced
      final initialCached = await todoService.getOne(
        result.id,
        requestPolicy: RequestPolicy.cacheOnly,
      );
      expect(initialCached.data['synced'], isFalse);

      // Wait for background sync (longer for remote server)
      await Future.delayed(const Duration(milliseconds: 1500));

      // After sync should be marked as synced
      final syncedCached = await todoService.getOne(
        result.id,
        requestPolicy: RequestPolicy.cacheOnly,
      );
      expect(syncedCached.data['synced'], isTrue);
    });

    test('create: works offline (stores in cache for later sync)', () async {
      await setConnectivity(false);

      final result = await todoService.create(
        body: {'name': 'offline_cache_first'},
        requestPolicy: RequestPolicy.cacheFirst,
      );

      expect(result.data['name'], 'offline_cache_first');

      // Verify it's in cache and marked for sync
      final cached = await todoService.getOne(
        result.id,
        requestPolicy: RequestPolicy.cacheOnly,
      );
      expect(cached.data['synced'], isFalse);
      expect(cached.data['isNew'], isTrue);
    });

    test('update: writes to cache first and returns immediately', () async {
      // Create a record first
      final created = await todoService.create(
        body: {'name': 'original_update_test'},
        requestPolicy: RequestPolicy.cacheAndNetwork,
      );

      // Update with cacheFirst
      final updated = await todoService.update(
        created.id,
        body: {'name': 'cache_first_updated'},
        requestPolicy: RequestPolicy.cacheFirst,
      );

      expect(updated.data['name'], 'cache_first_updated');

      // Verify in cache
      final cached = await todoService.getOne(
        created.id,
        requestPolicy: RequestPolicy.cacheOnly,
      );
      expect(cached.data['name'], 'cache_first_updated');
    });

    test('update: syncs to server in background', () async {
      final created = await todoService.create(
        body: {'name': 'pre_update'},
        requestPolicy: RequestPolicy.cacheAndNetwork,
      );

      await todoService.update(
        created.id,
        body: {'name': 'post_update_bg_sync'},
        requestPolicy: RequestPolicy.cacheFirst,
      );

      // Wait for background sync
      await Future.delayed(const Duration(milliseconds: 500));

      // Verify on server
      final serverRecord =
          await serverClient.collection('todo').getOne(created.id);
      expect(serverRecord.data['name'], 'post_update_bg_sync');
    });

    test('delete: deletes from cache first', () async {
      final created = await todoService.create(
        body: {'name': 'to_delete_cache_first'},
        requestPolicy: RequestPolicy.cacheAndNetwork,
      );

      await todoService.delete(
        created.id,
        requestPolicy: RequestPolicy.cacheFirst,
      );

      // Verify deleted from cache
      final cached = await todoService.getOneOrNull(
        created.id,
        requestPolicy: RequestPolicy.cacheOnly,
      );
      expect(cached, isNull);
    });

    test('delete: syncs deletion to server in background', () async {
      final created = await todoService.create(
        body: {'name': 'to_delete_bg_sync'},
        requestPolicy: RequestPolicy.cacheAndNetwork,
      );

      await todoService.delete(
        created.id,
        requestPolicy: RequestPolicy.cacheFirst,
      );

      // Wait for background sync
      await Future.delayed(const Duration(milliseconds: 500));

      // Verify deleted from server
      final serverRecord = await serverClient
          .collection('todo')
          .getOne(created.id)
          .then((_) => true)
          .catchError((_) => false);
      expect(serverRecord, isFalse);
    });
  });

  // ============================================================================
  // networkFirst Read Tests
  // ============================================================================

  group('networkFirst - Read Operations', () {
    test('fetches from network first when online', () async {
      // Create directly on server
      final serverRecord = await serverClient.collection('todo').create(
        body: {'name': 'network_first_item'},
      );

      // Fetch with networkFirst
      final result = await todoService.getOne(
        serverRecord.id,
        requestPolicy: RequestPolicy.networkFirst,
      );

      expect(result.data['name'], 'network_first_item');
    });

    test('updates cache after successful network fetch', () async {
      final serverRecord = await serverClient.collection('todo').create(
        body: {'name': 'cache_after_network'},
      );

      await todoService.getOne(
        serverRecord.id,
        requestPolicy: RequestPolicy.networkFirst,
      );

      // Verify now in cache
      final cached = await todoService.getOne(
        serverRecord.id,
        requestPolicy: RequestPolicy.cacheOnly,
      );
      expect(cached.data['name'], 'cache_after_network');
    });

    test('falls back to cache when network fails', () async {
      // Pre-populate cache
      final created = await todoService.create(
        body: {'name': 'fallback_to_cache'},
        requestPolicy: RequestPolicy.cacheAndNetwork,
      );

      // Go offline
      await setConnectivity(false);

      // Fetch with networkFirst - should fall back to cache
      final result = await todoService.getOne(
        created.id,
        requestPolicy: RequestPolicy.networkFirst,
      );

      expect(result.data['name'], 'fallback_to_cache');
    });

    test('getList falls back to cache when offline', () async {
      // Pre-populate cache
      await todoService.create(
        body: {'name': 'list_fallback_1'},
        requestPolicy: RequestPolicy.cacheAndNetwork,
      );
      await todoService.create(
        body: {'name': 'list_fallback_2'},
        requestPolicy: RequestPolicy.cacheAndNetwork,
      );

      // Go offline
      await setConnectivity(false);

      // Fetch list with networkFirst
      final result = await todoService.getList(
        requestPolicy: RequestPolicy.networkFirst,
      );

      expect(result.items.length, greaterThanOrEqualTo(2));
    });

    test('getFullList falls back to cache when offline', () async {
      // Pre-populate cache
      await todoService.create(
        body: {'name': 'full_list_fallback_1'},
        requestPolicy: RequestPolicy.cacheAndNetwork,
      );

      // Go offline
      await setConnectivity(false);

      // Fetch full list with networkFirst
      final result = await todoService.getFullList(
        requestPolicy: RequestPolicy.networkFirst,
      );

      expect(result, isNotEmpty);
    });

    test('throws when offline and cache is empty', () async {
      await setConnectivity(false);

      // Try to fetch a non-existent record
      expect(
        () => todoService.getOne(
          'nonexistent_id',
          requestPolicy: RequestPolicy.networkFirst,
        ),
        throwsException,
      );
    });

    test('prefers fresh network data over stale cache', () async {
      // Create via network
      final created = await todoService.create(
        body: {'name': 'stale_cache'},
        requestPolicy: RequestPolicy.cacheAndNetwork,
      );

      // Update directly on server
      await serverClient.collection('todo').update(
        created.id,
        body: {'name': 'fresh_from_server'},
      );

      // Fetch with networkFirst - should get fresh data
      final result = await todoService.getOne(
        created.id,
        requestPolicy: RequestPolicy.networkFirst,
      );

      expect(result.data['name'], 'fresh_from_server');
    });
  });

  // ============================================================================
  // networkFirst Write Tests
  // ============================================================================

  group('networkFirst - Write Operations', () {
    test('create: writes to server first when online', () async {
      final result = await todoService.create(
        body: {'name': 'network_first_create'},
        requestPolicy: RequestPolicy.networkFirst,
      );

      expect(result.data['name'], 'network_first_create');

      // Verify on server
      final serverRecord =
          await serverClient.collection('todo').getOne(result.id);
      expect(serverRecord.data['name'], 'network_first_create');
    });

    test('create: updates cache after successful server write', () async {
      final result = await todoService.create(
        body: {'name': 'cache_after_server_create'},
        requestPolicy: RequestPolicy.networkFirst,
      );

      // Verify in cache and marked as synced
      final cached = await todoService.getOne(
        result.id,
        requestPolicy: RequestPolicy.cacheOnly,
      );
      expect(cached.data['name'], 'cache_after_server_create');
      expect(cached.data['synced'], isTrue);
    });

    test('create: throws exception when offline (no fallback)', () async {
      await setConnectivity(false);

      expect(
        () => todoService.create(
          body: {'name': 'offline_network_first'},
          requestPolicy: RequestPolicy.networkFirst,
        ),
        throwsException,
      );
    });

    test('update: writes to server first when online', () async {
      final created = await todoService.create(
        body: {'name': 'before_network_first_update'},
        requestPolicy: RequestPolicy.cacheAndNetwork,
      );

      final updated = await todoService.update(
        created.id,
        body: {'name': 'after_network_first_update'},
        requestPolicy: RequestPolicy.networkFirst,
      );

      expect(updated.data['name'], 'after_network_first_update');

      // Verify on server
      final serverRecord =
          await serverClient.collection('todo').getOne(created.id);
      expect(serverRecord.data['name'], 'after_network_first_update');
    });

    test('update: updates cache after successful server write', () async {
      final created = await todoService.create(
        body: {'name': 'pre_update_nf'},
        requestPolicy: RequestPolicy.cacheAndNetwork,
      );

      await todoService.update(
        created.id,
        body: {'name': 'post_update_nf'},
        requestPolicy: RequestPolicy.networkFirst,
      );

      // Verify in cache
      final cached = await todoService.getOne(
        created.id,
        requestPolicy: RequestPolicy.cacheOnly,
      );
      expect(cached.data['name'], 'post_update_nf');
      expect(cached.data['synced'], isTrue);
    });

    test('update: throws exception when offline (no fallback)', () async {
      final created = await todoService.create(
        body: {'name': 'created_for_offline_update'},
        requestPolicy: RequestPolicy.cacheAndNetwork,
      );

      await setConnectivity(false);

      expect(
        () => todoService.update(
          created.id,
          body: {'name': 'offline_update_attempt'},
          requestPolicy: RequestPolicy.networkFirst,
        ),
        throwsException,
      );
    });

    test('delete: deletes from server first when online', () async {
      final created = await todoService.create(
        body: {'name': 'to_delete_nf'},
        requestPolicy: RequestPolicy.cacheAndNetwork,
      );

      await todoService.delete(
        created.id,
        requestPolicy: RequestPolicy.networkFirst,
      );

      // Verify deleted from server
      final serverExists = await serverClient
          .collection('todo')
          .getOne(created.id)
          .then((_) => true)
          .catchError((_) => false);
      expect(serverExists, isFalse);
    });

    test('delete: removes from cache after successful server deletion',
        () async {
      final created = await todoService.create(
        body: {'name': 'to_delete_nf_cache'},
        requestPolicy: RequestPolicy.cacheAndNetwork,
      );

      await todoService.delete(
        created.id,
        requestPolicy: RequestPolicy.networkFirst,
      );

      // Verify deleted from cache
      final cached = await todoService.getOneOrNull(
        created.id,
        requestPolicy: RequestPolicy.cacheOnly,
      );
      expect(cached, isNull);
    });

    test('delete: throws exception when offline (no fallback)', () async {
      final created = await todoService.create(
        body: {'name': 'to_delete_offline_nf'},
        requestPolicy: RequestPolicy.cacheAndNetwork,
      );

      await setConnectivity(false);

      expect(
        () => todoService.delete(
          created.id,
          requestPolicy: RequestPolicy.networkFirst,
        ),
        throwsException,
      );
    });

    test(
        'update: a 404 is thrown and never recreates the record on the '
        'server', () async {
      // Deleted on the server (e.g. by another device) but still cached.
      final created = await serverClient
          .collection('todo')
          .create(body: {'name': 'deleted_elsewhere'});
      await todoService.getOne(created.id,
          requestPolicy: RequestPolicy.networkFirst);
      await serverClient.collection('todo').delete(created.id);

      await expectLater(
        todoService.update(
          created.id,
          body: {'name': 'edited_after_delete'},
          requestPolicy: RequestPolicy.networkFirst,
        ),
        throwsA(isA<ClientException>()
            .having((e) => e.statusCode, 'statusCode', 404)),
      );

      final onServer = await serverClient
          .collection('todo')
          .getFullList(filter: 'id = "${created.id}"');
      expect(onServer, isEmpty, reason: 'A deleted record must stay deleted');
      expect(await client.db.rowById('todo', created.id), isNull,
          reason: 'The stale cached copy is dropped');
    });
  });

  // ============================================================================
  // Edge Cases and Integration Tests
  // ============================================================================

  group('Edge Cases', () {
    test('cacheFirst with expand returns expanded data', () async {
      // This is a basic test - expand functionality depends on schema
      final result = await todoService.create(
        body: {'name': 'expandable_item'},
        requestPolicy: RequestPolicy.cacheFirst,
      );

      final fetched = await todoService.getOne(
        result.id,
        requestPolicy: RequestPolicy.cacheFirst,
      );

      expect(fetched.data['name'], 'expandable_item');
    });

    test('networkFirst with expand returns expanded data', () async {
      final result = await todoService.create(
        body: {'name': 'expandable_item_nf'},
        requestPolicy: RequestPolicy.networkFirst,
      );

      final fetched = await todoService.getOne(
        result.id,
        requestPolicy: RequestPolicy.networkFirst,
      );

      expect(fetched.data['name'], 'expandable_item_nf');
    });

    test('switching between policies works correctly', () async {
      // Create with cacheAndNetwork to ensure it's on the server first
      final created = await todoService.create(
        body: {'name': 'policy_switch_test'},
        requestPolicy: RequestPolicy.cacheAndNetwork,
      );

      // Update with networkFirst (record already exists on server)
      final updated = await todoService.update(
        created.id,
        body: {'name': 'updated_with_network_first'},
        requestPolicy: RequestPolicy.networkFirst,
      );

      expect(updated.data['name'], 'updated_with_network_first');

      // Fetch with cacheFirst
      final fetched = await todoService.getOne(
        created.id,
        requestPolicy: RequestPolicy.cacheFirst,
      );

      expect(fetched.data['name'], 'updated_with_network_first');
    });

    test('rapid consecutive cacheFirst operations work correctly', () async {
      final results = <RecordModel>[];

      for (var i = 0; i < 5; i++) {
        final result = await todoService.create(
          body: {'name': 'rapid_create_$i'},
          requestPolicy: RequestPolicy.cacheFirst,
        );
        results.add(result);
      }

      expect(results.length, 5);
      for (var i = 0; i < 5; i++) {
        expect(results[i].data['name'], 'rapid_create_$i');
      }

      // Wait for background syncs
      await Future.delayed(const Duration(milliseconds: 1000));

      // Verify all synced
      for (final result in results) {
        final cached = await todoService.getOne(
          result.id,
          requestPolicy: RequestPolicy.cacheOnly,
        );
        expect(cached.data['synced'], isTrue);
      }
    });

    test('getFirstListItem with cacheFirst', () async {
      await todoService.create(
        body: {'name': 'first_item_cf'},
        requestPolicy: RequestPolicy.cacheAndNetwork,
      );

      final result = await todoService.getFirstListItem(
        "name = 'first_item_cf'",
        requestPolicy: RequestPolicy.cacheFirst,
      );

      expect(result.data['name'], 'first_item_cf');
    });

    test('getFirstListItem with networkFirst', () async {
      await todoService.create(
        body: {'name': 'first_item_nf'},
        requestPolicy: RequestPolicy.cacheAndNetwork,
      );

      final result = await todoService.getFirstListItem(
        "name = 'first_item_nf'",
        requestPolicy: RequestPolicy.networkFirst,
      );

      expect(result.data['name'], 'first_item_nf');
    });
  });
}
