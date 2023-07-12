import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pocketbase_drift/pocketbase_drift.dart';

import 'test_data/collections.json.dart';

void main() {
  final connection = DatabaseConnection(NativeDatabase.memory());
  final db = DataBase(connection);
  final collections = [...offlineCollections]
      .map((e) => CollectionModel.fromJson(jsonDecode(jsonEncode(e))))
      .toList();
  late final todoCollection = collections.firstWhere((e) => e.name == 'todo');
  final todo = todoCollection.name;

  group('data test', () {
    setUpAll(() async {
      await db.setSchema(collections.map((e) => e.toJson()).toList());
    });

    test('check', () async {
      final result = await db.$query(todo).get();

      expect(result, []);
    });

    test('create', () async {
      final result = await db.$create(
        todo,
        {'name': 'test'},
      );

      expect(result['name'], 'test');
      expect(result['id'], isNotEmpty);

      await db.$delete(
        todo,
        result['id'],
      );
    });

    test('update', () async {
      final result = await db.$create(
        todo,
        {'name': 'test'},
      );

      final updated = await db.$update(
        todo,
        result['id'],
        {'name': 'test2'},
      );

      expect(updated['name'], 'test2');
      expect(updated['id'], result['id']);

      await db.$delete(
        todo,
        result['id'],
      );
    });

    test('delete', () async {
      final result = await db.$create(
        todo,
        {'name': 'test'},
      );

      await db.$delete(
        todo,
        result['id'],
      );

      final results = await db.$query(todo).get();

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
            todo,
            item,
          );

          expect(result['name'], item['name']);

          final updated = await db.$update(
            todo,
            result['id'],
            {'name': 'test2'},
          );

          expect(updated['name'], 'test2');
          expect(updated['id'], result['id']);

          await db.$delete(
            todo,
            result['id'],
          );
        });

        final results = await db.$query(todo).get();

        expect(results, []);
      });
    });
  });
}
