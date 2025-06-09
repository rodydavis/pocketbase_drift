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

  tearDownAll(() async {
    try {
      final remoteItems = await todoService.getFullList(
          requestPolicy: RequestPolicy.networkOnly);
      for (final item in remoteItems) {
        await todoService.delete(item.id,
            requestPolicy: RequestPolicy.networkOnly);
      }
    } catch (_) {}
  });

  group('Records CRUD (Offline Policies)', () {
    for (final requestPolicy in [
      RequestPolicy.cacheOnly,
      RequestPolicy.cacheAndNetwork
    ]) {
      group(requestPolicy.name, () {
        setUp(() async {
          // Ensure a clean slate before each test in this group
          await client.db.deleteAll('todo');
        });

        test('create', () async {
          final item = await todoService.create(
            body: {'name': 'test_create_${requestPolicy.name}'},
            requestPolicy: requestPolicy,
          );
          expect(item.data['name'], 'test_create_${requestPolicy.name}');
          final cachedItem = await todoService.getOneOrNull(item.id,
              requestPolicy: RequestPolicy.cacheOnly);
          expect(cachedItem, isNotNull);
          if (requestPolicy == RequestPolicy.cacheOnly) {
            expect(cachedItem!.data['synced'], isFalse);
            expect(cachedItem.data['isNew'], isTrue);
            expect(cachedItem.data['noSync'], isTrue);
          } else {
            expect(cachedItem!.data['synced'], isTrue);
          }
        });

        test('update', () async {
          final initialItem = await todoService.create(
            body: {'name': 'test_update_initial_${requestPolicy.name}'},
            requestPolicy: RequestPolicy.cacheAndNetwork,
          );
          final updated = await todoService.update(
            initialItem.id,
            body: {'name': 'test_update_final_${requestPolicy.name}'},
            requestPolicy: requestPolicy,
          );
          expect(
              updated.data['name'], 'test_update_final_${requestPolicy.name}');
          if (requestPolicy == RequestPolicy.cacheOnly) {
            final cached = await todoService.getOneOrNull(initialItem.id,
                requestPolicy: RequestPolicy.cacheOnly);
            expect(cached!.data['synced'], isFalse);
            expect(cached.data['noSync'], isTrue);
          }
        });

        test('delete', () async {
          final item = await todoService.create(
            body: {'name': 'test_delete_${requestPolicy.name}'},
            requestPolicy: RequestPolicy.cacheAndNetwork,
          );
          await todoService.delete(item.id, requestPolicy: requestPolicy);
          if (requestPolicy == RequestPolicy.cacheOnly) {
            final deletedCacheItem = await todoService.getOneOrNull(item.id,
                requestPolicy: RequestPolicy.cacheOnly);
            expect(deletedCacheItem, isNotNull);
            expect(deletedCacheItem!.data['deleted'], isTrue);
            expect(deletedCacheItem.data['noSync'], isTrue);
          } else {
            final cacheDeletedItem = await todoService.getOneOrNull(item.id,
                requestPolicy: RequestPolicy.cacheOnly);
            expect(cacheDeletedItem, isNull);
          }
        });
      });
    }
  });
}
