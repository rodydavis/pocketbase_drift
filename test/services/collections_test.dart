import 'dart:convert';
import 'dart:io' as io;
import 'package:drift/drift.dart';
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

  late final $PocketBase client;
  late final db = client.db;
  final collections = [...offlineCollections]
      .map((e) => CollectionModel.fromJson(jsonDecode(jsonEncode(e))))
      .toList();

  group('collections service', () {
    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('dev.fluttercommunity.plus/connectivity'),
        (MethodCall methodCall) async {
          if (methodCall.method == 'check') {
            return <String>['wifi']; // Report that we are connected to wifi
          }
          return null;
        },
      );

      hierarchicalLoggingEnabled = true;
      Logger.root.level = Level.ALL;
      Logger.root.onRecord.listen((record) {
        // ignore: avoid_print
        print('${record.level.name}: ${record.time}: ${record.message}');
        if (record.error != null) {
          // ignore: avoid_print
          print('Error: ${record.error}');
        }
      });

      client = $PocketBase.database(
        url,
        authStore:
            $AuthStore((await SharedPreferences.getInstance()), 'pb_auth'),
        inMemory: true,
        connection: DatabaseConnection(NativeDatabase.memory()),
      );

      await client.collection('_superusers').authWithPassword(
            username,
            password,
          );

      await db.setSchema(collections.map((e) => e.toJson()).toList());
    });

    tearDownAll(() async {
      //
    });

    test('check if added locally', () async {
      final local = await client.collections.getFullList(
        requestPolicy: RequestPolicy.cacheOnly,
      );

      expect(local, isNotEmpty);
    });

    test('get by name local', () async {
      const target = 'todo';
      final collectionId = collections.firstWhere((e) => e.name == target).id;

      final collection = await client.collections.getOneOrNull(
        collectionId,
        requestPolicy: RequestPolicy.cacheOnly,
      );

      expect(collection != null, true);
      expect(collection!.name, target);
      expect(collection.id, collectionId);
    });

    test('get by name remote', () async {
      const target = 'todo';
      final collectionId = collections.firstWhere((e) => e.name == target).id;

      final collection = await client.collections.getOneOrNull(
        collectionId,
        requestPolicy: RequestPolicy.networkOnly,
      );

      expect(collection != null, true);
      expect(collection!.name, target);
      expect(collection.id, collectionId);
    });

    group('get by name or id', () {
      for (final requestPolicy in [
        RequestPolicy.networkOnly,
        RequestPolicy.cacheAndNetwork,
        RequestPolicy.cacheOnly,
      ]) {
        test(requestPolicy.name, () async {
          const targetName = 'todo';
          final targetId =
              collections.firstWhere((e) => e.name == targetName).id;

          final idList = await client.collections.getList(
            filter: 'id = "$targetId"',
            requestPolicy: requestPolicy,
          );

          expect(idList.items.isNotEmpty, true);
          expect(idList.items.first.id, targetId);
          expect(idList.items.first.name, targetName);

          final nameList = await client.collections.getList(
            filter: 'name = "$targetName"',
            requestPolicy: requestPolicy,
          );

          expect(nameList.items.isNotEmpty, true);
          expect(nameList.items.first.id, targetId);
          expect(nameList.items.first.name, targetName);

          final itemId = await client.collections.getFirstListItem(
            'id = "$targetId" || name = "$targetId"',
            requestPolicy: requestPolicy,
          );

          expect(itemId.id, targetId);
          expect(itemId.name, targetName);

          final itemName = await client.collections.getFirstListItem(
            'id = "$targetName" || name = "$targetName"',
            requestPolicy: requestPolicy,
          );

          expect(itemName.id, targetId);
          expect(itemName.name, targetName);
        });
      }
    });

    test('client collection records', () async {
      const target = 'todo';

      final collection = await client.$collection(target);

      expect(collection.service, target);
    });
  });
}
