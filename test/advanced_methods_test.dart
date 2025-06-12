import 'dart:convert';
import 'dart:io' as io;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:pocketbase_drift/pocketbase_drift.dart';

import 'test_data/collections.json.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  io.HttpOverrides.global = null;

  group('Advanced Data Methods', () {
    late $PocketBase client;
    late $RecordService todoService;
    final collections = [...offlineCollections]
        .map((e) => CollectionModel.fromJson(jsonDecode(jsonEncode(e))))
        .toList();

    setUpAll(() async {
      hierarchicalLoggingEnabled = true;
      Logger.root.level = Level.ALL;
      Logger.root.onRecord.listen((record) {
        // ignore: avoid_print
        print('${record.level.name}: ${record.time}: ${record.message}');
      });

      // Mock connectivity to be online for these tests
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel('dev.fluttercommunity.plus/connectivity'),
              (MethodCall methodCall) async => ['wifi']);
    });

    // Use setUp to get a fresh client and DB for each test, ensuring isolation
    setUp(() async {
      client = $PocketBase.database(
        'http://localhost', // Dummy URL for local tests
        inMemory: true,
      );
      client.logging = true;
      await client.db.setSchema(collections.map((e) => e.toJson()).toList());
      todoService = await client.$collection('todo');
    });

    test('watchRecord streams a single record and its updates', () async {
      final initialRecord = await todoService.create(
        body: {'name': 'Watch Me'},
        requestPolicy: RequestPolicy.cacheOnly,
      );

      final stream = todoService.watchRecord(initialRecord.id,
          requestPolicy: RequestPolicy.cacheOnly);

      // Use expectLater to handle the stream events
      expectLater(
        stream,
        emitsInOrder([
          // 1. Initial event: The record as it was created
          isA<RecordModel>().having((r) => r.data['name'], 'name', 'Watch Me'),
          // 2. Second event: The record after being updated
          isA<RecordModel>()
              .having((r) => r.data['name'], 'name', 'I Am Watched'),
          // 3. Third event: null after the record is deleted
          isA<RecordModel>()
              .having((r) => r.data['deleted'], 'deleted', isTrue),
        ]),
      );

      // Give the stream a moment to emit the first item before we update
      await Future.delayed(const Duration(milliseconds: 50));

      // Trigger the second event by updating the record
      await todoService.update(
        initialRecord.id,
        body: {'name': 'I Am Watched'},
        requestPolicy: RequestPolicy.cacheOnly,
      );

      // Give it another moment
      await Future.delayed(const Duration(milliseconds: 50));

      // Trigger the third event by deleting the record

      // Since the network will fail (dummy URL), this will mark the record as deleted locally.
      await todoService.delete(
        initialRecord.id,
        requestPolicy: RequestPolicy.cacheAndNetwork,
      );
    });

    test('\$count returns the correct number of records', () async {
      // Initially, the count should be 0
      expect(await client.db.$count(todoService.service), 0);

      // Add some records
      await todoService.create(
          body: {'name': 'Count 1'}, requestPolicy: RequestPolicy.cacheOnly);
      await todoService.create(
          body: {'name': 'Count 2'}, requestPolicy: RequestPolicy.cacheOnly);

      // Check the count
      expect(await client.db.$count(todoService.service), 2);

      // Add one more
      await todoService.create(
          body: {'name': 'Count 3'}, requestPolicy: RequestPolicy.cacheOnly);
      expect(await client.db.$count(todoService.service), 3);
    });

    test('mergeLocal only writes new or updated records', () async {
      final now = DateTime.now();
      final record1Data = {
        'id': 'rec1',
        'name': 'Record One',
        'created': now.toIso8601String(),
        'updated': now.toIso8601String()
      };
      final record2Data = {
        'id': 'rec2',
        'name': 'Record Two',
        'created': now.toIso8601String(),
        'updated': now.toIso8601String()
      };

      // 1. Set an initial state in the database
      await client.db.setLocal(todoService.service, [record1Data, record2Data]);
      expect(await client.db.$count(todoService.service), 2);

      // 2. Prepare a list for merging.
      // - record1Data is identical (should be skipped)
      // - A new version of record2Data (should be updated)
      // - A completely new record3Data (should be inserted)
      final updatedRecord2Data = {
        'id': 'rec2',
        'name': 'Record Two - Updated',
        'created': now.toIso8601String(),
        'updated': now.add(const Duration(minutes: 1)).toIso8601String()
      };
      final newRecord3Data = {
        'id': 'rec3',
        'name': 'Record Three',
        'created': now.toIso8601String(),
        'updated': now.toIso8601String()
      };

      final mergeList = [record1Data, updatedRecord2Data, newRecord3Data];

      // 3. Perform the merge
      await client.db.mergeLocal(todoService.service, mergeList);

      // 4. Verify the final state of the database
      // The total count should now be 3
      expect(await client.db.$count(todoService.service), 3);

      // Verify the content of each record
      final finalRecord1 = await todoService.getOne('rec1',
          requestPolicy: RequestPolicy.cacheOnly);
      final finalRecord2 = await todoService.getOne('rec2',
          requestPolicy: RequestPolicy.cacheOnly);
      final finalRecord3 = await todoService.getOne('rec3',
          requestPolicy: RequestPolicy.cacheOnly);

      // Record 1 should be unchanged
      expect(finalRecord1.data['name'], 'Record One');

      // Record 2 should be updated
      expect(finalRecord2.data['name'], 'Record Two - Updated');

      // Record 3 should exist
      expect(finalRecord3, isNotNull);
      expect(finalRecord3.data['name'], 'Record Three');
    });
  });
}
