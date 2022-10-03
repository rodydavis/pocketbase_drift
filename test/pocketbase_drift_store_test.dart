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
  const url = 'http://127.0.0.1:8090';

  late final PocketBaseDrift client;

  setUpAll(() async {
    client = PocketBaseDrift(
      url,
      connection: DatabaseConnection(NativeDatabase.memory()),
    );
    await client.pocketbase.admins.authViaEmail(
      username,
      password,
    );
  });

  test('check if client is created', () {
    expect(client.url, url);
  });

  test('check records call', () async {
    final remote = await client.pocketbase.records.getFullList('todo');
    final local = await client.getRecords('todo');

    expect(remote, isNotEmpty);
    expect(local, isNotEmpty);
    expect(local.length, remote.length);
  });

  test('check record call', () async {
    final remote = await client.pocketbase.records.getFullList('todo');

    final first = remote.first;
    final result = await client.getRecord('todo', first.id);

    expect(first.id, result?.id);
  });

  test('check new record update', () async {
    final records = await client.getRecords('todo');

    final item = await client.pocketbase.records.create('todo', body: {
      'name': 'test',
    });

    final remote = await client.pocketbase.records.getFullList('todo');

    expect(remote, isNotEmpty);
    expect(remote.length, records.length + 1);

    // Server and cache should update
    final newItems = await client.getRecords('todo');
    expect(newItems.length, remote.length);

    // Delete item
    await client.pocketbase.records.delete('todo', item.id);
  });

  test(
    'check 1000 records',
    () async {
      // Add 1000 records
      for (var i = 0; i < 1000; i++) {
        await client.addRecord('todo', {
          'name': 'test $i',
        });
        debugPrint('added $i / 1000');
      }

      final local = await client.getRecords('todo');

      expect(local.length >= 1000, true);
    },
    skip: true,
  );

  test('test search', () async {
    final a = await client.addRecord('todo', {
      'name': 'This is a test',
    });
    final b = await client.addRecord('todo', {
      'name': 'This (is) a test',
    });
    final c = await client.addRecord('todo', {
      'name': 'This "is" a - test',
    });
    final d = await client.addRecord('todo', {
      'name': 'This also is a test',
    });

    final local = await client.getRecords('todo');
    final search = await client.search('this is a test', collection: 'todo');

    expect(local.length >= 4, true);
    expect(search.isNotEmpty, true);

    await client.deleteRecord('todo', a.id);
    await client.deleteRecord('todo', b.id);
    await client.deleteRecord('todo', c.id);
    await client.deleteRecord('todo', d.id);
  });

  test('check for double inserts', () async {
    final item = await client.pocketbase.records.create('todo', body: {
      'name': 'test item',
    });

    // Insert into database
    final id1 = await client.database.setRecord(item);
    final id2 = await client.database.setRecord(item);

    // Expect id1 to be missing from database
    final result = await client.database.get(id1);
    expect(result, null);

    // Expect id2 to be present in database
    final result2 = await client.database.get(id2);
    expect(result2 != null, true);
  });

  test('check collection stream progress', () async {
    final stream = client.updateCollection('todo');
    final results = <double>[];

    await for (final progress in stream) {
      debugPrint('progress: $progress');
      results.add(progress);
    }

    expect(results, isNotEmpty);
    expect(results.first, 0.0);
    expect(results.last, 1.0);
  });

  test('check offline', () async {
    final records = await client.getRecords('todo');

    // Call records again offline
    PocketBaseHttpClient.offline = true;
    final local = await client.getRecords('todo');

    expect(local, isNotEmpty);
    expect(local.length, records.length);

    PocketBaseHttpClient.offline = false;
  });
}
