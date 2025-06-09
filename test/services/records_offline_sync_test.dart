import 'dart:convert';
import 'dart:io' as io;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
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
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel('dev.fluttercommunity.plus/connectivity'),
              (MethodCall methodCall) async {
        if (methodCall.method == 'check') {
          return isOnline ? <String>['wifi'] : <String>['none'];
        }
        return null;
      });
      // Manually trigger a status update in our service to simulate the change
      await client.connectivity.checkConnectivity();
    }

    setUpAll(() async {
      hierarchicalLoggingEnabled = true;
      Logger.root.level = Level.ALL;
      Logger.root.onRecord.listen((record) {
        // ignore: avoid_print
        print('${record.level.name}: ${record.time}: ${record.message}');
      });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel('dev.fluttercommunity.plus/connectivity'),
              (MethodCall methodCall) async {
        if (methodCall.method == 'check') {
          return <String>['wifi'];
        }
        return null;
      });

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

      final remainingPending = await todoCollection.pending().get();
      expect(remainingPending, isEmpty,
          reason:
              "There should be no pending records after a successful sync.");

      final oldLocalRecord = await todoCollection.getOneOrNull(
        offlineRecord.id,
        requestPolicy: RequestPolicy.cacheOnly,
      );
      expect(oldLocalRecord, isNull,
          reason: "The temporary local record should be deleted after sync.");

      final newLocalRecord = await todoCollection.getOneOrNull(
        serverRecord.id,
        requestPolicy: RequestPolicy.cacheOnly,
      );
      expect(newLocalRecord, isNotNull,
          reason:
              "The synced record from the server should be in the local cache.");
      expect(newLocalRecord!.id, serverRecord.id);
      expect(newLocalRecord.data['synced'], isTrue,
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

      final deletedLocal = await todoCollection.getOne(initialRecord.id,
          requestPolicy: RequestPolicy.cacheOnly);
      expect(deletedLocal.data['deleted'], true);
      expect(deletedLocal.data['synced'], false);

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
  });
}
