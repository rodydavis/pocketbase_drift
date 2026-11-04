import 'dart:convert';
import 'dart:io' as io;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:pocketbase_drift/pocketbase_drift.dart';

import '../test_data/collections.json.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  io.HttpOverrides.global = null;
  group('Offline Sync Tests', () {
    late $PocketBase client;
    late PocketBase serverClient;
    const url = 'http://127.0.0.1:8090';
    final collections = [...offlineCollections]
        .map((e) => CollectionModel.fromJson(jsonDecode(jsonEncode(e))))
        .toList();

    // Test helper to control the mock connectivity status
    Future<void> setConnectivity(bool isOnline) async {
      ConnectivityService.enableProbes = false;
      client.connectivity.setConnectivityStatus(isOnline);
    }

    setUpAll(() async {
      hierarchicalLoggingEnabled = true;
      Logger.root.level = Level.ALL;
      Logger.root.onRecord.listen((record) {
        // ignore: avoid_print
        print('${record.level.name}: ${record.time}: ${record.message}');
      });
      ConnectivityService.enableProbes = false;

      client = $PocketBase.database(
        url,
        inMemory: true,
      );
      client.logging = true;
      await client.db.setSchema(collections.map((e) => e.toJson()).toList());
      await client
          .collection('_superusers')
          .authWithPassword('test@admin.com', 'Password123');

      // Initialize the second client
      serverClient = PocketBase(url);
      await serverClient
          .collection('_superusers')
          .authWithPassword('test@admin.com', 'Password123');
    });

    tearDownAll(() {
      client.close();
    });

    // Use tearDown to clean data between each test for isolation
    tearDown(() async {
      await setConnectivity(true);
      final todoCollection = client.collection('todo');
      try {
        final items = await todoCollection.getFullList(
            requestPolicy: RequestPolicy.networkOnly);
        for (final item in items) {
          await todoCollection.delete(item.id,
              requestPolicy: RequestPolicy.networkOnly);
        }
      } catch (_) {}
      await client.db.deleteAll(todoCollection.service);
    });

    test('should sync pending records when connectivity is restored', () async {
      final todoCollection = client.collection('todo');
      final recordName =
          'offline_sync_test_${DateTime.now().millisecondsSinceEpoch}';

      await setConnectivity(false);
      expect(client.connectivity.isConnected, isFalse);

      final offlineRecord = await todoCollection.create(
        body: {'name': recordName},
        requestPolicy: RequestPolicy.cacheAndNetwork,
      );
      expect(offlineRecord, isNotNull);
      expect(offlineRecord.id, isNotEmpty);

      final pendingRecords = await todoCollection.pending().get();
      expect(pendingRecords.length, equals(1),
          reason:
              "Record created with cacheAndNetwork while offline should be pending.");
      expect(pendingRecords.first.id, equals(offlineRecord.id));

      await setConnectivity(true);
      expect(client.connectivity.isConnected, isTrue);

      // Add a microtask delay to allow the sync process to be initiated
      await Future.delayed(Duration.zero);

      await client.syncCompleted;

      final serverRecordList = await todoCollection.getFullList(
        filter: "name = '$recordName'",
        requestPolicy: RequestPolicy.networkOnly,
      );
      expect(serverRecordList.length, 1,
          reason: "Record should be found on the server after sync.");
      final serverRecord = serverRecordList.first;
      expect(serverRecord.data['name'], equals(recordName));

      // With PocketBase-compatible IDs, the local ID and server ID are now the same
      expect(serverRecord.id, equals(offlineRecord.id),
          reason: "Server should use the same PocketBase-compatible local ID.");

      final remainingPending = await todoCollection.pending().get();
      expect(remainingPending, isEmpty,
          reason:
              "There should be no pending records after a successful sync.");

      // The local record should still exist (with the same ID) and be marked as synced
      final localRecord = await todoCollection.getOneOrNull(
        offlineRecord.id,
        requestPolicy: RequestPolicy.cacheOnly,
      );
      expect(localRecord, isNotNull,
          reason:
              "The local record should still exist with the same ID after sync.");
      expect(localRecord!.id, equals(serverRecord.id));
      expect(localRecord.data['synced'], isTrue,
          reason: "The local record should be marked as synced.");
    });

    test(
        'should sync a delete action even if the record was updated first offline',
        () async {
      final todoCollection = client.collection('todo');

      final initialRecord = await todoCollection.create(
        body: {'name': 'initial_name'},
        requestPolicy: RequestPolicy.cacheAndNetwork,
      );
      expect(initialRecord, isNotNull);

      await setConnectivity(false);

      await todoCollection.update(
        initialRecord.id,
        body: {'name': 'updated_name_offline'},
        requestPolicy: RequestPolicy.cacheAndNetwork,
      );

      final updatedLocal = await todoCollection.getOne(initialRecord.id,
          requestPolicy: RequestPolicy.cacheOnly);
      expect(updatedLocal.data['name'], 'updated_name_offline');
      expect(updatedLocal.data['synced'], false);

      await todoCollection.delete(initialRecord.id,
          requestPolicy: RequestPolicy.cacheAndNetwork);

      // The tombstone is hidden from reads but kept for the sync queue.
      final deletedLocal = await todoCollection.getOneOrNull(initialRecord.id,
          requestPolicy: RequestPolicy.cacheOnly);
      expect(deletedLocal, isNull,
          reason: "Offline-deleted records must be hidden from local reads.");
      final pendingAfterDelete = await todoCollection.pending().get();
      expect(pendingAfterDelete.map((r) => r.id), contains(initialRecord.id),
          reason: "The deletion must remain queued for sync.");

      await setConnectivity(true);
      await Future.delayed(Duration.zero);
      await client.syncCompleted;

      final serverRecord = await todoCollection.getOneOrNull(initialRecord.id,
          requestPolicy: RequestPolicy.networkOnly);
      expect(serverRecord, isNull,
          reason: "Record should be deleted from the server.");

      final finalLocalRecord = await todoCollection.getOneOrNull(
          initialRecord.id,
          requestPolicy: RequestPolicy.cacheOnly);
      expect(finalLocalRecord, isNull,
          reason: "Record should be deleted from the local cache after sync.");

      final pending = await todoCollection.pending().get();
      expect(pending, isEmpty, reason: "Pending queue should be empty.");
    });

    test(
        'should overwrite server changes with offline changes ("last write wins")',
        () async {
      final todoClient = client.collection('todo');
      final todoServer = serverClient.collection('todo');

      final initialRecord = await todoClient.create(
        body: {'name': 'initial_state'},
        requestPolicy: RequestPolicy.cacheAndNetwork,
      );

      await todoServer.update(
        initialRecord.id,
        body: {'name': 'server_update_state'},
      );

      await setConnectivity(false);

      await todoClient.update(
        initialRecord.id,
        body: {'name': 'offline_final_state'},
        requestPolicy: RequestPolicy.cacheAndNetwork,
      );

      await setConnectivity(true);
      await Future.delayed(Duration.zero);
      await client.syncCompleted;

      final finalServerRecord = await todoServer.getOne(initialRecord.id);
      expect(finalServerRecord.data['name'], 'offline_final_state',
          reason: "Offline change should overwrite the server change.");

      final finalLocalRecord = await todoClient.getOne(initialRecord.id,
          requestPolicy: RequestPolicy.cacheOnly);
      expect(finalLocalRecord.data['name'], 'offline_final_state');
      expect(finalLocalRecord.data['synced'], true);
    });

    test('should sync files created offline when connectivity is restored',
        () async {
      final ultimateService = await client.$collection('ultimate');
      final serverUltimate = serverClient.collection('ultimate');

      // Go offline
      await setConnectivity(false);
      expect(client.connectivity.isConnected, isFalse);

      // Create a record with a file while offline
      const testFileName = 'sync_test_file.txt';
      const testFileContent = 'This file was created offline and should sync!';
      final fileBytes = Uint8List.fromList(testFileContent.codeUnits);

      final testFile = http.MultipartFile.fromBytes(
        'file_single',
        fileBytes,
        filename: testFileName,
      );

      final offlineRecord = await ultimateService.create(
        body: {'plain_text': 'record_with_file_for_sync'},
        files: [testFile],
        requestPolicy: RequestPolicy.cacheAndNetwork,
      );

      // Verify record was created locally with file
      expect(offlineRecord.data['file_single'], isNotNull);
      expect(offlineRecord.data['file_single'], testFileName);

      // Verify file blob was cached
      final cachedFile = await client.db
          .getFile(offlineRecord.id, testFileName)
          .getSingleOrNull();
      expect(cachedFile, isNotNull,
          reason: 'File blob should be cached when created offline');

      // Verify record is pending
      final pendingRecords = await ultimateService.pending().get();
      expect(pendingRecords.length, 1);

      // Restore connectivity and sync
      await setConnectivity(true);
      expect(client.connectivity.isConnected, isTrue);
      await Future.delayed(Duration.zero);
      await client.syncCompleted;

      // Verify record was synced to server
      final serverRecord = await serverUltimate.getOne(offlineRecord.id);
      expect(serverRecord, isNotNull);
      expect(serverRecord.data['plain_text'], 'record_with_file_for_sync');

      // Verify file was uploaded (server renamed it)
      final serverFileName = serverRecord.data['file_single'] as String?;
      expect(serverFileName, isNotNull,
          reason: 'File should be uploaded to server');
      expect(serverFileName, isNotEmpty);
      expect(serverFileName, startsWith('sync_test_file_'),
          reason: 'Server should rename file with unique suffix');

      // Clean up
      await serverUltimate.delete(offlineRecord.id);
      await client.db.deleteAll('ultimate');
    });

    test(
        'should purge a record that was created and deleted offline (no sync limbo)',
        () async {
      final todoCollection = client.collection('todo');
      final recordName = 'limbo_purge_${DateTime.now().millisecondsSinceEpoch}';

      await setConnectivity(false);

      final offlineRecord = await todoCollection.create(
        body: {'name': recordName},
        requestPolicy: RequestPolicy.cacheAndNetwork,
      );
      await todoCollection.delete(offlineRecord.id,
          requestPolicy: RequestPolicy.cacheAndNetwork);

      // The record never reached the server.
      final serverListBefore =
          await serverClient.collection('todo').getFullList(
                filter: "name = '$recordName'",
              );
      expect(serverListBefore, isEmpty,
          reason: 'Record was created offline; server must not know it.');

      // Nothing to delete on the server: the row is purged right away, not
      // kept as a tombstone retrying a doomed server delete.
      final pendingBefore = await todoCollection.pending().get();
      expect(pendingBefore.map((r) => r.id), isNot(contains(offlineRecord.id)));
      expect(await client.db.rowById('todo', offlineRecord.id), isNull,
          reason:
              'Locally-created deleted record must be purged, not left in limbo.');

      await setConnectivity(true);
      await Future.delayed(Duration.zero);
      await client.syncCompleted;

      final serverListAfter = await serverClient.collection('todo').getFullList(
            filter: "name = '$recordName'",
          );
      expect(serverListAfter, isEmpty,
          reason: 'Nothing should have been created on the server.');
    });

    test('should purge a tombstone when the server no longer has the record',
        () async {
      final todoCollection = client.collection('todo');
      final todoServer = serverClient.collection('todo');

      final record = await todoCollection.create(
        body: {
          'name': 'tombstone_404_${DateTime.now().millisecondsSinceEpoch}'
        },
        requestPolicy: RequestPolicy.cacheAndNetwork,
      );

      await setConnectivity(false);
      await todoCollection.delete(record.id,
          requestPolicy: RequestPolicy.cacheAndNetwork);

      // Another device deletes the record on the server while we are offline.
      await todoServer.delete(record.id);

      await setConnectivity(true);
      await Future.delayed(Duration.zero);
      await client.syncCompleted;

      expect((await todoCollection.pending().get()), isEmpty,
          reason: 'Queue should not retry the 404 delete forever.');

      final row = await client.db
          .$query('todo', filter: "id = '${record.id}'", includeDeleted: true)
          .getSingleOrNull();
      expect(row, isNull,
          reason: 'Tombstone should be dropped when the server is already '
              'missing the record.');
    });

    test(
        'should hide tombstones from cacheOnly reads, counts and search while keeping them pending',
        () async {
      final todoCollection = client.collection('todo');
      final recordName =
          'tombstone_hidden_${DateTime.now().millisecondsSinceEpoch}';

      final record = await todoCollection.create(
        body: {'name': recordName},
        requestPolicy: RequestPolicy.cacheAndNetwork,
      );

      await setConnectivity(false);
      await todoCollection.delete(record.id,
          requestPolicy: RequestPolicy.cacheAndNetwork);

      final visible = await todoCollection.getFullList(
          requestPolicy: RequestPolicy.cacheOnly);
      expect(visible.map((r) => r.id), isNot(contains(record.id)),
          reason: 'getFullList must exclude offline-deleted records.');

      final oneOrNull = await todoCollection.getOneOrNull(record.id,
          requestPolicy: RequestPolicy.cacheOnly);
      expect(oneOrNull, isNull,
          reason: 'getOneOrNull must not surface offline-deleted records.');

      final count = await client.db.$count('todo');
      expect(
        count,
        0,
        reason: 'Counts must exclude offline-deleted records.',
      );

      final hits = await client.db.search(recordName, service: 'todo').get();
      expect(hits, isEmpty,
          reason: 'Search must exclude offline-deleted records.');

      final pending = await todoCollection.pending().get();
      expect(pending.map((r) => r.id), contains(record.id),
          reason: 'The deletion must remain queued for sync.');
    });

    test('mergeLocal must not resurrect a pending-delete tombstone', () async {
      final todoCollection = client.collection('todo');

      final record = await todoCollection.create(
        body: {'name': 'no_resurrect_${DateTime.now().millisecondsSinceEpoch}'},
        requestPolicy: RequestPolicy.cacheAndNetwork,
      );

      await setConnectivity(false);
      await todoCollection.delete(record.id,
          requestPolicy: RequestPolicy.cacheAndNetwork);

      // A background list fetch lands while the deletion is still pending:
      // the server still returns the record, but mergeLocal must keep the
      // tombstone instead of writing the stale server copy over it.
      await client.db.mergeLocal('todo', [
        {
          'id': record.id,
          'name': 'stale_server_copy',
          'updated': DateTime.now().toUtc().toIso8601String()
        },
      ]);

      final visible = await todoCollection.getFullList(
          requestPolicy: RequestPolicy.cacheOnly);
      expect(visible.map((r) => r.id), isNot(contains(record.id)),
          reason: 'Server data must not resurrect the pending delete.');

      final pending = await todoCollection.pending().get();
      expect(pending.map((r) => r.id), contains(record.id),
          reason: 'The tombstone must survive the merge.');

      // Sync still completes normally afterwards.
      await setConnectivity(true);
      await Future.delayed(Duration.zero);
      await client.syncCompleted;

      final row = await client.db
          .$query('todo', filter: "id = '${record.id}'", includeDeleted: true)
          .getSingleOrNull();
      expect(row, isNull);
    });

    test('offline delete removes the record from watchRecords streams',
        () async {
      final todoCollection = client.collection('todo');
      final recordName =
          'watch_delete_${DateTime.now().millisecondsSinceEpoch}';

      final record = await todoCollection.create(
        body: {'name': recordName},
        requestPolicy: RequestPolicy.cacheAndNetwork,
      );
      expect(
        (await todoCollection.getFullList(
                requestPolicy: RequestPolicy.cacheOnly))
            .map((r) => r.id),
        contains(record.id),
        reason: 'Record is visible before the offline delete.',
      );

      // Warm the stream BEFORE the delete so it observes both states.
      final emissions = <List<RecordModel>>[];
      final subscription = todoCollection
          .watchRecords(
            filter: "name = '$recordName'",
            requestPolicy: RequestPolicy.cacheOnly,
          )
          .listen(emissions.add);
      // Give the cold stream a moment to produce its initial snapshot.
      await Future<void>.delayed(const Duration(milliseconds: 150));

      await setConnectivity(false);
      await todoCollection.delete(record.id,
          requestPolicy: RequestPolicy.cacheAndNetwork);
      await setConnectivity(true);
      await Future.delayed(Duration.zero);
      await client.syncCompleted;
      // Allow the drift watch to flush its re-emission.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await subscription.cancel();

      expect(emissions, isNotEmpty, reason: 'The stream must emit.');
      expect(emissions.last, isEmpty,
          reason: 'The tombstone must not surface in the stream.');
    });
  });
}
