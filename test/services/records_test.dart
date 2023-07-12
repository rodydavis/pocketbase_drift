import 'dart:convert';
import 'dart:io' as io;
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pocketbase_drift/pocketbase_drift.dart';
import 'package:pocketbase_drift/src/pocketbase/services/service.dart';

import '../data/collections.json.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  io.HttpOverrides.global = null;

  const username = 'test@admin.com';
  const password = 'Password123';
  const url = 'http://127.0.0.1:3000';

  late final $PocketBase client;
  late final db = client.db;
  final collections = [...offlineCollections].map((e) => CollectionModel.fromJson(jsonDecode(jsonEncode(e)))).toList();

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
            fetchPolicy: fetchPolicy,
          );

          expect(item.data['name'], 'test1');

          await service.delete(item.id);
        });

        test('update', () async {
          final item = await service.create(
            body: {
              'name': 'test1',
            },
            fetchPolicy: fetchPolicy,
          );

          expect(item.data['name'], 'test1');

          final updated = await service.update(
            item.id,
            body: {
              'name': 'test2',
            },
            fetchPolicy: fetchPolicy,
          );

          expect(updated.data['name'], 'test2');

          await service.delete(item.id);
        });

        test('delete', () async {
          final item = await service.create(
            body: {
              'name': 'test1',
            },
            fetchPolicy: fetchPolicy,
          );

          expect(item.data['name'], 'test1');

          await service.delete(item.id);

          final deleted = await service.getOneOrNull(
            item.id,
            fetchPolicy: FetchPolicy.cacheOnly,
          );

          expect(deleted == null, true);
        });

        test('realtime', () async {
          final item1 = await service.create(
            body: {
              'name': 'test1',
            },
          );
          final item2 = await service.create(
            body: {
              'name': 'test2',
            },
            fetchPolicy: fetchPolicy,
          );

          final stream = service.watchRecords(
            fetchPolicy: fetchPolicy,
          );
          final events = await stream.toList();

          expect(events.isNotEmpty, true);
          expect(events[0], [
            item1,
            item2,
          ]);

          expect(item1.data['name'], 'test1');
          expect(item2.data['name'], 'test2');

          await service.delete(item1.id);
          await service.delete(item2.id);
        });
      });
    }
  });
}
