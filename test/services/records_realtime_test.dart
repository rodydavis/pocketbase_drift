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
  });

  group('Records Realtime', () {
    test('all', () async {
      await client.db.deleteAll(todoService.service);

      final item1 = await todoService.create(
        body: {'name': 'test1_rt_all'},
        requestPolicy: RequestPolicy.cacheAndNetwork,
      );
      final item2 = await todoService.create(
        body: {'name': 'test2_rt_all'},
        requestPolicy: RequestPolicy.cacheAndNetwork,
      );

      final local =
          await todoService.getFullList(requestPolicy: RequestPolicy.cacheOnly);
      expect(local.length, 2);

      final stream = todoService.watchRecords();
      final events = await stream.take(1).toList();

      expect(events.isNotEmpty, true);
      expect(events[0].length, 2);

      expect(events[0].any((e) => e.id == item1.id), isTrue);
      expect(events[0].any((e) => e.id == item2.id), isTrue);

      await todoService.delete(item1.id,
          requestPolicy: RequestPolicy.cacheAndNetwork);
      await todoService.delete(item2.id,
          requestPolicy: RequestPolicy.cacheAndNetwork);
    });

    test('filter', () async {
      await client.db.deleteAll(todoService.service);

      final item1 = await todoService.create(
        body: {'name': 'test1_rt_filter'},
        requestPolicy: RequestPolicy.cacheAndNetwork,
      );
      // ignore: unused_local_variable
      final item2 = await todoService.create(
        body: {'name': 'test2_rt_filter'},
        requestPolicy: RequestPolicy.cacheAndNetwork,
      );

      final local = await todoService.getFullList(
          filter: "name = 'test1_rt_filter'",
          requestPolicy: RequestPolicy.cacheOnly);
      expect(local.length, 1);
      expect(local[0].id, item1.id);

      final stream =
          todoService.watchRecords(filter: "name = 'test1_rt_filter'");
      final events = await stream.take(1).toList();

      expect(events.isNotEmpty, true);
      expect(events[0].length, 1);
      expect(events[0][0].id, item1.id);

      await todoService.delete(item1.id,
          requestPolicy: RequestPolicy.cacheAndNetwork);
      await todoService.delete(item2.id,
          requestPolicy: RequestPolicy.cacheAndNetwork);
    });
  });
}
