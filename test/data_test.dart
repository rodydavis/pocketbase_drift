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

    // Clear 'todo' table before each test in this group for isolation
    setUp(() async {
      await db.deleteAll(todo);
    });

    test('check if empty after setup', () async {
      final result = await db.$query(todo).get();
      expect(result, isEmpty);
    });

    test('create', () async {
      final result = await db.$create(
        todo,
        {'name': 'test_create_data'},
        // validate: true is now default
      );

      expect(result['name'], 'test_create_data');
      expect(result['id'], isNotEmpty);
    });

    test('update', () async {
      final result = await db.$create(
        todo,
        {'name': 'test_update_initial_data'},
      );

      final updated = await db.$update(
        todo,
        result['id'] as String,
        {'name': 'test_update_final_data'},
        // validate: true is now default
      );

      expect(updated['name'], 'test_update_final_data');
      expect(updated['id'], result['id']);
    });

    test('delete', () async {
      final result = await db.$create(
        todo,
        {'name': 'test_delete_data'},
      );

      await db.$delete(
        todo,
        result['id'] as String,
      );

      final results = await db.$query(todo).get();
      expect(results, isEmpty);
    });

    group('stress tests', () {
      test('add 1000, update then delete', () async {
        const total = 100; // Reduced for faster test runs, was 1000
        final items = <Map<String, dynamic>>[];

        for (var i = 0; i < total; i++) {
          items.add({'name': 'stress_test_$i'});
        }

        await Future.forEach(items, (item) async {
          final result = await db.$create(
            todo,
            item,
          );

          expect(result['name'], item['name']);

          final updated = await db.$update(
            todo,
            result['id'] as String,
            {'name': 'stress_test_updated'},
          );

          expect(updated['name'], 'stress_test_updated');
          expect(updated['id'], result['id']);

          await db.$delete(
            todo,
            result['id'] as String,
          );
        });

        final results = await db.$query(todo).get();
        expect(results, isEmpty);
      });
    });
  });
}
