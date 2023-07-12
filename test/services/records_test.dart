import 'dart:convert';
import 'dart:io' as io;
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pocketbase_drift/pocketbase_drift.dart';
import 'package:pocketbase_drift/src/pocketbase/services/service.dart';

import '../collections.json.dart';

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

  late final $RecordService service;

  group('records service', () {
    setUpAll(() async {
      client = $PocketBase.database(
        url,
        inMemory: true,
        connection: DatabaseConnection(NativeDatabase.memory()),
        httpClientFactory: () => PocketBaseHttpClient.retry(retries: 1),
      );

      await client.admins.authWithPassword(
        username,
        password,
      );

      await db.setSchema(collections.map((e) => e.toJson()).toList());

      service = await client.$collection('todo');
    });

    tearDownAll(() async {
      final local = await service.getFullList();
      for (final item in local) {
        await service.delete(item.id);
      }
    });

    test('check if empty', () async {
      final local = await service.getFullList();

      expect(local, isEmpty);
    });

    for (final fetchPolicy in [
      FetchPolicy.networkOnly,
      FetchPolicy.cacheOnly,
      FetchPolicy.cacheAndNetwork,
    ]) {
      group(fetchPolicy.name, () {
        test('create', () async {
          final item = await service.create(
            body: {
              'name': 'test1',
            },
          );

          expect(item.data['name'], 'test1');

          await service.delete(item.id);
        });

        test('update', () async {
          final item = await service.create(
            body: {
              'name': 'test1',
            },
          );

          expect(item.data['name'], 'test1');

          final updated = await service.update(
            item.id,
            body: {
              'name': 'test2',
            },
          );

          expect(updated.data['name'], 'test2');

          await service.delete(item.id);
        });

        test('delete', () async {
          final item = await service.create(
            body: {
              'name': 'test1',
            },
          );

          expect(item.data['name'], 'test1');

          await service.delete(item.id);

          final deleted = await service.getOneOrNull(
            item.id,
            fetchPolicy: FetchPolicy.cacheOnly,
          );

          expect(deleted == null, true);
        });
      });
    }
  });
}
