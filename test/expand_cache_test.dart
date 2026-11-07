import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pocketbase_drift/pocketbase_drift.dart';

import 'test_data/collections.json.dart';

/// Tests for expanded record caching behavior.
///
/// This test validates that when records are fetched with nested expand,
/// the related records are cached to their respective collection tables
/// so they can be queried independently later.

void main() {
  final connection = DatabaseConnection(NativeDatabase.memory());
  final db = DataBase(connection);
  final collections = [...offlineCollections]
      .map((e) => CollectionModel.fromJson(jsonDecode(jsonEncode(e))))
      .toList();

  const todo = 'todo';
  const ultimate = 'ultimate';
  const users = 'users';

  setUpAll(() async {
    await db.setSchema(collections.map((e) => e.toJson()).toList());
    await db.deleteAll(todo);
    await db.deleteAll(ultimate);
    await db.deleteAll(users);
  });

  tearDown(() async {
    await db.deleteAll(todo);
    await db.deleteAll(ultimate);
    await db.deleteAll(users);
  });

  group('Expanded record caching', () {
    test('nested expanded records are cached to their collections', () async {
      // This test simulates the scenario:
      // 1. Create a record with nested expand data (as if returned from server)
      // 2. The nested records should be cached to their respective collections
      // 3. Later queries to those collections should find the records

      // Clear all tables first
      await db.deleteAll(users);
      await db.deleteAll(todo);
      await db.deleteAll(ultimate);

      // Simulate server response with nested expand
      // In real scenario, server returns this and we cache it
      final userId = 'user_from_expand';
      final todoId = 'todo_from_expand';

      final ultimateWithExpand = {
        'plain_text': 'Ultimate with Nested',
        'relation_single': todoId,
        'expand': {
          'relation_single': {
            'id': todoId,
            'name': 'Todo from Expand',
            'user': userId,
            'created': DateTime.now().toIso8601String(),
            'updated': DateTime.now().toIso8601String(),
            'expand': {
              'user': {
                'id': userId,
                'name': 'User from Expand',
                'email': 'test@example.com',
                'created': DateTime.now().toIso8601String(),
                'updated': DateTime.now().toIso8601String(),
              },
            },
          },
        },
      };

      // Save the ultimate record - this should also cache the nested records
      await db.$create(ultimate, ultimateWithExpand);

      // Now query the todo collection - the todo should be there
      final todoResult =
          await db.$query(todo, filter: "id = '$todoId'").getSingleOrNull();

      expect(todoResult, isNotNull,
          reason: 'Todo should be cached from expand');
      expect(todoResult!['name'], 'Todo from Expand');

      // Query the users collection - the user should also be there
      final userResult =
          await db.$query(users, filter: "id = '$userId'").getSingleOrNull();

      expect(userResult, isNotNull,
          reason: 'User should be cached from nested expand');
      expect(userResult!['name'], 'User from Expand');

      // Now query todo with expand - it should work because user is cached
      final todoWithExpand = await db
          .$query(todo, expand: 'user', filter: "id = '$todoId'")
          .getSingleOrNull();

      expect(todoWithExpand, isNotNull);
      expect(todoWithExpand!['expand'], isNotNull);
      expect(todoWithExpand['expand']['user'], isNotNull);
      expect(todoWithExpand['expand']['user']['name'], 'User from Expand');
    });

    test('multi-level nested expand caches all levels', () async {
      // Create records at each level
      final user = await db.$create(users, {'name': 'Deep Nested User'});
      final todoItem = await db.$create(todo, {
        'name': 'Deep Nested Todo',
        'user': user['id'],
      });

      // Simulate an ultimate record coming from server with 2-level expand
      final ultimateData = {
        'plain_text': 'Ultimate Deep',
        'relation_single': todoItem['id'],
        'expand': {
          'relation_single': {
            ...todoItem,
            'expand': {
              'user': user,
            },
          },
        },
      };

      await db.$create(ultimate, ultimateData);

      // Verify: Query todo WITHOUT expand first to confirm it was cached
      final todoCached = await db
          .$query(todo, filter: "id = '${todoItem['id']}'")
          .getSingleOrNull();

      expect(todoCached, isNotNull);
      expect(todoCached!['name'], 'Deep Nested Todo');

      // Verify: Query user to confirm it was also cached
      final userCached = await db
          .$query(users, filter: "id = '${user['id']}'")
          .getSingleOrNull();

      expect(userCached, isNotNull);
      expect(userCached!['name'], 'Deep Nested User');
    });

    test('multi-relation expand caches all related records', () async {
      // Create multiple related items
      final todo1 = await db.$create(todo, {'name': 'Multi 1'});
      final todo2 = await db.$create(todo, {'name': 'Multi 2'});
      final todo3 = await db.$create(todo, {'name': 'Multi 3'});

      // Clear the todo table to prove records come from expand caching
      await db.deleteAll(todo);

      // Simulate an ultimate with multi-relation expand from server
      final ultimateData = {
        'plain_text': 'Multi Relation',
        'relation_multi': [todo1['id'], todo2['id'], todo3['id']],
        'expand': {
          'relation_multi': [todo1, todo2, todo3],
        },
      };

      await db.$create(ultimate, ultimateData);

      // All three todos should now be cached
      final cachedTodos = await db.$query(todo).get();
      expect(cachedTodos.length, 3);

      final names = cachedTodos.map((t) => t['name']).toSet();
      expect(names, containsAll(['Multi 1', 'Multi 2', 'Multi 3']));
    });

    test('expand field is not stored in cached related records', () async {
      // When caching related records, we should strip the expand field
      // to avoid stale nested expand data

      final user = await db.$create(users, {'name': 'User with stale expand'});

      final todoWithUser = {
        'name': 'Todo to cache',
        'user': user['id'],
        'expand': {
          'user': user,
        },
      };

      // Clear todo table
      await db.deleteAll(todo);

      // Create ultimate with nested expand
      final ultimateData = {
        'plain_text': 'Check expand strip',
        'relation_single': 'todo_id_123',
        'expand': {
          'relation_single': {
            ...todoWithUser,
            'id': 'todo_id_123',
          },
        },
      };

      await db.$create(ultimate, ultimateData);

      // The cached todo should NOT have an expand field stored
      final cachedTodo =
          await db.$query(todo, filter: "id = 'todo_id_123'").getSingleOrNull();

      expect(cachedTodo, isNotNull);
      expect(cachedTodo!['name'], 'Todo to cache');
      // The cached todo should not have expand in its data
      // (it will be computed dynamically when queried with expand)
      expect(cachedTodo['expand'], isNull);
    });
  });
}
