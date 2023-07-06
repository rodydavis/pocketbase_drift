import 'dart:io' as io;
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pocketbase_drift/pocketbase_drift.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  io.HttpOverrides.global = null;

  const username = 'test@admin.com';
  const password = 'Password123';
  const url = 'http://127.0.0.1:3000';

  late final $PocketBase client;
  late final CollectionModel collection;

  late final $RecordService col;

  setUpAll(() async {
    final connection = DatabaseConnection(NativeDatabase.memory());
    client = $PocketBase(url, connection: connection);
    await client.admins.authWithPassword(
      username,
      password,
    );
    collection = await client.collections.getOne('l1qxa33evkxxte0');

    await client.db.collectionsDao.createItem(collection.toModel());

    col = client.$collection(collection);

    // // Add records
    const total = 25;
    for (var i = 0; i < total; i++) {
      await col.create(
        body: {'name': 'test $i'},
      );
      debugPrint('added $i / $total');
    }
  });

  tearDownAll(() async {
    final local = await col.getFullList();
    for (final item in local) {
      await col.delete(
        item.id,
        // fetchPolicy: FetchPolicy.networkOnly,
        // TODO: Fails on anything else
      );
    }
  });

  test('check collections', () async {
    final local = await client.db.collectionsDao.getAll();

    expect(local, isNotEmpty);
  });

  // TODO: Check for files

  // TODO: Sorting, filtering, fields

  test('check record call', () async {
    final remote = await col.getFullList();

    final first = remote.first;
    final result = await client.db.recordsDao.get(
      first.id,
      collection: collection.id,
    );

    expect(first.id, result?.id);
  });

  test('check new record update', () async {
    final records = await col.getFullList();

    final item = await col.create(body: {
      'name': 'test',
    });

    final remote = await col.getFullList();

    expect(
      remote,
      isNotEmpty,
      reason: 'Remote should not be empty',
    );
    expect(
      remote.length,
      records.length + 1,
      reason: 'Remote should be 1 more',
    );

    // Server and cache should update
    final newItems = await client.db.recordsDao.getAll(
      collection: collection.id,
    );
    expect(
      newItems.length,
      remote.length,
      reason: 'Cache should update',
    );

    // Delete item
    await col.delete(item.id);
  });

  test(
    'check 1000 records',
    () async {
      // Add 1000 records
      for (var i = 0; i < 1000; i++) {
        await col.create(body: {
          'name': 'test $i',
        });
        debugPrint('added $i / 1000');
      }

      final local = await client.db.recordsDao.getAll(
        collection: collection.id,
      );

      expect(local.length >= 1000, true);
    },
    skip: true,
  );

  // test('test search', () async {
  //   final a = await client.db.addRecord('todo', {
  //     'name': 'This is a test',
  //   });
  //   final b = await client.db.addRecord('todo', {
  //     'name': 'This (is) a test',
  //   });
  //   final c = await client.db.addRecord('todo', {
  //     'name': 'This "is" a - test',
  //   });
  //   final d = await client.db.addRecord('todo', {
  //     'name': 'This also is a test',
  //   });

  //   final local = await client.db.getRecords('todo');
  //   final search = await client.search('this is a test', collection: 'todo');

  //   expect(local.length >= 4, true);
  //   expect(search.isNotEmpty, true);

  //   await client.db.remove(a);
  //   await client.db.remove(b);
  //   await client.db.remove(c);
  //   await client.db.remove(d);
  // });

  // test('check for double inserts', () async {
  //   final item = await col.create(body: {
  //     'name': 'test item',
  //   });

  //   // Insert into database
  //   final id1 = await client.db.recordsDao.updateRecordModel(
  //     collectionId: collection.id,
  //     item: item,
  //   );
  //   final id2 = await client.db.recordsDao.updateRecordModel(
  //     collectionId: collection.id,
  //     item: item,
  //   );

  //   // Expect id1 to be missing from database
  //   final result = await client.db.get(id1.id);
  //   expect(result, null);

  //   // Expect id2 to be present in database
  //   final result2 = await client.db.get(id2.id);
  //   expect(result2 != null, true);
  // });

  group('fetch policy tests', () {
    test('cache only', () async {
      final item = await col.create(
        body: {'name': 'test'},
        fetchPolicy: FetchPolicy.cacheOnly,
      );

      final remote = await col.getOneOrNull(
        item.id,
        fetchPolicy: FetchPolicy.networkOnly,
      );
      final local = await col.getOneOrNull(
        item.id,
        fetchPolicy: FetchPolicy.cacheOnly,
      );

      expect(remote == null, true);
      expect(local != null, true);

      // Delete item
      await col.delete(
        item.id,
        fetchPolicy: FetchPolicy.cacheOnly,
      );
    });
    test('network only', () async {
      final item = await col.create(
        body: {'name': 'test'},
        fetchPolicy: FetchPolicy.networkOnly,
      );

      final remote = await col.getOneOrNull(
        item.id,
        fetchPolicy: FetchPolicy.networkOnly,
      );
      final local = await col.getOneOrNull(
        item.id,
        fetchPolicy: FetchPolicy.cacheOnly,
      );

      expect(remote != null, true);
      expect(local == null, true);

      // Delete item
      await col.delete(
        item.id,
        fetchPolicy: FetchPolicy.networkOnly,
      );
    });
    group('offline tests', () {
      test('creation', () async {
        final item = await col.create(
          body: {
            'name': 'test',
            'id': client.db.generateId(),
          },
          fetchPolicy: FetchPolicy.cacheOnly,
        );

        final remote = await col.getOneOrNull(
          item.id,
          fetchPolicy: FetchPolicy.networkOnly,
        );
        final local = await col.getOneOrNull(
          item.id,
          fetchPolicy: FetchPolicy.cacheOnly,
        );

        expect(remote == null, true);
        expect(local != null, true);

        // Delete item
        await col.delete(
          item.id,
          fetchPolicy: FetchPolicy.cacheOnly,
        );
      });
      test('mutation', () async {
        final item = await col.create(
          body: {'name': 'test'},
          fetchPolicy: FetchPolicy.cacheAndNetwork,
        );

        await col.update(item.id, body: {'name': 'test2'});

        await col.retryLocal().last;

        final remote = await col.getOneOrNull(
          item.id,
          fetchPolicy: FetchPolicy.networkOnly,
        );

        expect(remote != null, true);
        expect(remote?.getStringValue('name'), 'test2');

        // Delete item
        await col.delete(
          item.id,
          fetchPolicy: FetchPolicy.cacheOnly,
        );
      });
      test('deletion', () async {
        final item = await col.create(
          body: {'name': 'test'},
          fetchPolicy: FetchPolicy.cacheAndNetwork,
        );

        await col.delete(item.id, fetchPolicy: FetchPolicy.cacheOnly);

        await col.retryLocal().last;

        final remote = await col.getOneOrNull(
          item.id,
          fetchPolicy: FetchPolicy.networkOnly,
        );

        expect(remote == null, true);
      });
    });
  });
}
