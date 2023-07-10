import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pocketbase_drift/pocketbase_drift.dart';

import 'collections.json.dart';

void main() {
  final connection = DatabaseConnection(NativeDatabase.memory());
  final db = DataBase(connection);
  final collections = [...offlineCollections]
      .map((e) => CollectionModel.fromJson(jsonDecode(jsonEncode(e))))
      .map((e) => e.toModel(synced: true, deleted: false))
      .toList();
  late final todoCollection = collections.firstWhere((e) => e.name == 'todo');

  group('data test', () {
    setUpAll(() async {
      for (final collection in collections) {
        await db.collectionsDao.createItem(collection);
      }
    });

    test('check', () async {
      final result = await db.$query(todoCollection).get();

      expect(result, []);
    });

    test('create', () async {
      final result = await db.$create(
        todoCollection,
        {'name': 'test'},
      );

      expect(result['name'], 'test');
      expect(result['id'], isNotEmpty);

      await db.$delete(
        todoCollection,
        result['id'],
      );
    });

    test('update', () async {
      final result = await db.$create(
        todoCollection,
        {'name': 'test'},
      );

      final updated = await db.$update(
        todoCollection,
        result['id'],
        {'name': 'test2'},
      );

      expect(updated['name'], 'test2');
      expect(updated['id'], result['id']);

      await db.$delete(
        todoCollection,
        result['id'],
      );
    });

    test('delete', () async {
      final result = await db.$create(
        todoCollection,
        {'name': 'test'},
      );

      await db.$delete(
        todoCollection,
        result['id'],
      );

      final results = await db.$query(todoCollection).get();

      expect(results, []);
    });

    group('stress tests', () {
      test('add 1000, update then delete', () async {
        const total = 1000;
        final items = <Map<String, dynamic>>[];

        for (var i = 0; i < total; i++) {
          items.add({'name': 'test $i'});
        }

        await Future.forEach(items, (item) async {
          final result = await db.$create(
            todoCollection,
            item,
          );

          expect(result['name'], item['name']);

          final updated = await db.$update(
            todoCollection,
            result['id'],
            {'name': 'test2'},
          );

          expect(updated['name'], 'test2');
          expect(updated['id'], result['id']);

          await db.$delete(
            todoCollection,
            result['id'],
          );
        });

        final results = await db.$query(todoCollection).get();

        expect(results, []);
      });
    });
  });
}
