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

  group('Records CRUD (Online)', () {
    const requestPolicy = RequestPolicy.networkOnly;

    // Clean up all records in the service after each test in this group.
    tearDown(() async {
      try {
        final items =
            await todoService.getFullList(requestPolicy: requestPolicy);
        for (final item in items) {
          await todoService.delete(item.id, requestPolicy: requestPolicy);
        }
      } catch (_) {}
    });

    test('create', () async {
      final item = await todoService.create(
        body: {'name': 'test_create_online'},
        requestPolicy: requestPolicy,
      );
      expect(item.data['name'], 'test_create_online');
    });

    test('update', () async {
      final initialItem = await todoService.create(
        body: {'name': 'test_update_initial_online'},
        requestPolicy: requestPolicy,
      );
      final updated = await todoService.update(
        initialItem.id,
        body: {'name': 'test_update_final_online'},
        requestPolicy: requestPolicy,
      );
      expect(updated.data['name'], 'test_update_final_online');
    });

    test('delete', () async {
      final item = await todoService.create(
        body: {'name': 'test_delete_online'},
        requestPolicy: requestPolicy,
      );
      await todoService.delete(item.id, requestPolicy: requestPolicy);
      final refetched =
          await todoService.getOneOrNull(item.id, requestPolicy: requestPolicy);
      expect(refetched, isNull);
    });
  });
}
