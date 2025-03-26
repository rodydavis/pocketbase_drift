import 'dart:convert';
import 'dart:io' as io;
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pocketbase_drift/pocketbase_drift.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_data/collections.json.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  io.HttpOverrides.global = null;

  const username = 'test@admin.com';
  const password = 'Password123';
  const url = 'http://127.0.0.1:3000';

  late final $PocketBase client;
  late final db = client.db;
  final collections = [...offlineCollections]
      .map((e) => CollectionModel.fromJson(jsonDecode(jsonEncode(e))))
      .toList();

  group('collections service', () {
    setUpAll(() async {
      client = $PocketBase.database(
        url,
        authStore:
            $AuthStore((await SharedPreferences.getInstance()), 'pb_auth'),
        inMemory: true,
        connection: DatabaseConnection(NativeDatabase.memory()),
        httpClientFactory: () => PocketBaseHttpClient.retry(retries: 1),
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
        dataPolicy: DataPolicy.cacheOnly,
      );

      expect(local, isNotEmpty);
    });

    test('get by name local', () async {
      const target = 'todo';
      final collectionId = collections.firstWhere((e) => e.name == target).id;

      final collection = await client.collections.getOneOrNull(
        collectionId,
        dataPolicy: DataPolicy.cacheOnly,
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
        dataPolicy: DataPolicy.networkOnly,
      );

      expect(collection != null, true);
      expect(collection!.name, target);
      expect(collection.id, collectionId);
    });

    group('get by name or id', () {
      for (final dataPolicy in [
        DataPolicy.networkOnly,
        DataPolicy.cacheAndNetwork,
        DataPolicy.cacheOnly,
      ]) {
        test(dataPolicy.name, () async {
          const targetName = 'todo';
          final targetId =
              collections.firstWhere((e) => e.name == targetName).id;

          final idList = await client.collections.getList(
            filter: 'id = "$targetId"',
            dataPolicy: dataPolicy,
          );

          expect(idList.items.isNotEmpty, true);
          expect(idList.items.first.id, targetId);
          expect(idList.items.first.name, targetName);

          final nameList = await client.collections.getList(
            filter: 'name = "$targetName"',
            dataPolicy: dataPolicy,
          );

          expect(nameList.items.isNotEmpty, true);
          expect(nameList.items.first.id, targetId);
          expect(nameList.items.first.name, targetName);

          final itemId = await client.collections.getFirstListItem(
            'id = "$targetId" || name = "$targetId"',
            dataPolicy: dataPolicy,
          );

          expect(itemId.id, targetId);
          expect(itemId.name, targetName);

          final itemName = await client.collections.getFirstListItem(
            'id = "$targetName" || name = "$targetName"',
            dataPolicy: dataPolicy,
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
