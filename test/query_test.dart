import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull;
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
  final todoCollection = collections.firstWhere((e) => e.name == 'todo');
  final ultimateCollection =
      collections.firstWhere((e) => e.name == 'ultimate');

  final todo = todoCollection.name;
  final ultimate = ultimateCollection.name;

  setUpAll(() async {
    await db.setSchema(collections.map((e) => e.toJson()).toList());
    // Clear data before tests
    await db.deleteAll(todo);
    await db.deleteAll(ultimate);
  });

  tearDown(() async {
    // Clear data after each test
    await db.deleteAll(todo);
    await db.deleteAll(ultimate);
  });

  test('has collections', () async {
    final schema = await db.$collections().get();
    final result = await db.$query('schema', fields: 'id, name').get();
    final single = await db.$collections(service: todo).getSingleOrNull();

    expect(single != null, true);
    expect(single!.name, todo);
    expect(schema.isNotEmpty, true);
    expect(result.isNotEmpty, true);
    expect(schema.first.id, result.first['id']);
  });

  group('query test', () {
    test('empty if no data', () async {
      final result = await db.$query(todo, fields: 'id, name').get();
      expect(result, isEmpty);
    });

    test('single result', () async {
      final newItem = await db.$create(todo, {'name': 'test_single_res'});
      final result =
          await db.$query(todo, fields: 'id, name').getSingleOrNull();
      expect(result, isNotNull);
      expect(result!['name'], 'test_single_res');
      expect(result['id'], newItem['id']);
    });

    test('multiple results', () async {
      final newItem1 = await db.$create(todo, {'name': 'test_multi_1'});
      final newItem2 = await db.$create(todo, {'name': 'test_multi_2'});
      final result = await db
          .$query(todo, fields: 'id, name', sort: 'created')
          .get(); // Added sort for consistent order
      expect(result.length, 2);
      expect(result[0]['name'], 'test_multi_1');
      expect(result[0]['id'], newItem1['id']);
      expect(result[1]['name'], 'test_multi_2');
      expect(result[1]['id'], newItem2['id']);
    });

    test('query multiple results with filter', () async {
      await db.$create(todo, {'name': 'test_filter_1'});
      await db.$create(todo, {'name': 'test_filter_2'});
      final result = await db
          .$query(todo, fields: 'id, name', filter: 'name = \'test_filter_1\'')
          .get();
      expect(result.length, 1);
      expect(result[0]['name'], 'test_filter_1');
    });

    test('select specific fields', () async {
      await db.$create(todo, {'name': 'test_select_fields'});
      final result = await db
          .$query(todo, fields: 'name', filter: 'name = \'test_select_fields\'')
          .get();
      expect(result.length, 1);
      expect(result[0]['name'], 'test_select_fields');
      expect(result[0].keys.length, 1); // Only 'name' should be present
    });

    test('correct order with sort', () async {
      final newItem1 = await db.$create(todo, {
        'name': 'c_item',
        'created': DateTime(2023, 1, 1).toIso8601String()
      });
      final newItem2 = await db.$create(todo, {
        'name': 'a_item',
        'created': DateTime(2023, 1, 3).toIso8601String()
      });
      final newItem3 = await db.$create(todo, {
        'name': 'b_item',
        'created': DateTime(2023, 1, 2).toIso8601String()
      });

      final resultAsc =
          await db.$query(todo, fields: 'id, name', sort: 'created').get();
      expect(resultAsc.length, 3);
      expect(resultAsc[0]['id'], newItem1['id']);
      expect(resultAsc[1]['id'], newItem3['id']);
      expect(resultAsc[2]['id'], newItem2['id']);

      final resultDesc =
          await db.$query(todo, fields: 'id, name', sort: '-created').get();
      expect(resultDesc.length, 3);
      expect(resultDesc[0]['id'], newItem2['id']);
      expect(resultDesc[1]['id'], newItem3['id']);
      expect(resultDesc[2]['id'], newItem1['id']);
    });

    test('query with LIKE (~) operator', () async {
      await db.$create(todo, {'name': 'find_me_1'});
      await db.$create(todo, {'name': 'find_me_2'});
      await db.$create(todo, {'name': 'something_else'});

      final result = await db.$query(todo, filter: 'name ~ "find_me%"').get();
      expect(result.length, 2);
      expect(result.any((r) => r['name'] == 'find_me_1'), isTrue);
      expect(result.any((r) => r['name'] == 'find_me_2'), isTrue);
    });

    test('query with LIKE (~) operator and auto-wildcard', () async {
      await db.$create(todo, {'name': 'the quick brown fox'});
      await db.$create(todo, {'name': 'the slow brown turtle'});
      await db.$create(todo, {'name': 'a different animal'});

      // This should translate to `... LIKE '%brown%'`
      final result = await db.$query(todo, filter: 'name ~ "brown"').get();
      expect(result.length, 2,
          reason: "Should find two records containing 'brown'");

      // This should use the user-provided wildcard `... LIKE 'the slow%'`
      final resultWithWildcard =
          await db.$query(todo, filter: 'name ~ "the slow%"').get();
      expect(resultWithWildcard.length, 1);
      expect(resultWithWildcard.first['name'], 'the slow brown turtle');
    });

    test('query with NOT LIKE (!~) operator and auto-wildcard', () async {
      await db.$create(todo, {'name': 'the quick brown fox'});
      await db.$create(todo, {'name': 'the slow brown turtle'});
      await db.$create(todo, {'name': 'a different animal'});

      // This should translate to `... NOT LIKE '%brown%'`
      final result = await db.$query(todo, filter: 'name !~ "brown"').get();
      expect(result.length, 1);
      expect(result.first['name'], 'a different animal');
    });

    group('expand tests', () {
      test('single relation', () async {
        final relatedItem = await db.$create(todo, {'name': 'related_todo_1'});
        final mainItem = await db.$create(ultimate, {
          'plain_text': 'main_ultimate_1',
          'relation_single': relatedItem['id'],
        });

        final result = await db
            .$query(ultimate,
                expand: 'relation_single', filter: "id = '${mainItem['id']}'")
            .getSingleOrNull();
        expect(result, isNotNull);
        expect(result!['plain_text'], 'main_ultimate_1');
        expect(result['expand'], isNotNull);
        // Single relations (maxSelect == 1) are now returned as objects directly
        expect(result['expand']['relation_single'], isNotNull);
        expect(result['expand']['relation_single']['name'], 'related_todo_1');
      });

      test('indirect (nested) relation', () async {
        final user = await db.$create('users', {'name': 'Nested User'});
        expect(user['id'], isNotNull, reason: "User creation failed");

        final todoItem = await db.$create(todo, {
          'name': 'Todo with User Relation',
          'user': user['id'],
        });
        expect(todoItem['id'], isNotNull, reason: "Todo creation failed");

        final mainItem = await db.$create(ultimate, {
          'plain_text': 'Ultimate with Nested Relation',
          'relation_single': todoItem['id'],
        });
        expect(mainItem['id'], isNotNull, reason: "Ultimate creation failed");

        final result = await db
            .$query(ultimate,
                expand: 'relation_single.user',
                filter: "id = '${mainItem['id']}'")
            .getSingleOrNull();

        expect(result, isNotNull, reason: "The main item was not found");
        expect(result!['plain_text'], 'Ultimate with Nested Relation');

        expect(result['expand'], isNotNull,
            reason: "Top-level expand map is missing");
        // Single relations are now returned as objects directly (not lists)
        final expandedTodoRelation =
            result['expand']['relation_single'] as Map<String, dynamic>?;
        expect(expandedTodoRelation, isNotNull,
            reason: "First-level relation 'relation_single' was not expanded");

        expect(expandedTodoRelation!['name'], 'Todo with User Relation');

        expect(expandedTodoRelation['expand'], isNotNull,
            reason: "Nested expand map on the 'todo' item is missing");
        // Nested single relation is also returned as object directly
        final expandedUserRelation =
            expandedTodoRelation['expand']['user'] as Map<String, dynamic>?;
        expect(expandedUserRelation, isNotNull,
            reason: "Second-level relation 'user' was not expanded");

        expect(expandedUserRelation!['name'], 'Nested User',
            reason: "The deeply nested user data is incorrect");
        expect(expandedUserRelation['id'], user['id']);
      });

      test('multi relation with multiple related items', () async {
        final relatedItem1 =
            await db.$create(todo, {'name': 'multi_related_1'});
        final relatedItem2 =
            await db.$create(todo, {'name': 'multi_related_2'});
        final mainItem = await db.$create(ultimate, {
          'plain_text': 'main_ultimate_multi',
          'relation_multi': [
            relatedItem1['id'],
            relatedItem2['id']
          ], // List of IDs
        });

        final result = await db
            .$query(ultimate,
                expand: 'relation_multi', filter: "id = '${mainItem['id']}'")
            .getSingleOrNull();
        expect(result, isNotNull);
        expect(result!['plain_text'], 'main_ultimate_multi');
        expect(result['expand'], isNotNull);
        expect(result['expand']['relation_multi'], isNotNull);

        final expandedRelations = result['expand']['relation_multi'] as List;
        expect(expandedRelations.length, 2);

        // Check for presence of both items, order might not be guaranteed by DB unless sorted
        expect(
            expandedRelations.any((e) =>
                e['name'] == 'multi_related_1' &&
                e['id'] == relatedItem1['id']),
            isTrue);
        expect(
            expandedRelations.any((e) =>
                e['name'] == 'multi_related_2' &&
                e['id'] == relatedItem2['id']),
            isTrue);
      });

      test('multi relation with single related item (stored as list)',
          () async {
        final relatedItem1 =
            await db.$create(todo, {'name': 'multi_related_single_val'});
        final mainItem = await db.$create(ultimate, {
          'plain_text': 'main_ultimate_multi_single_val',
          'relation_multi': [relatedItem1['id']], // List with one ID
        });

        final result = await db
            .$query(ultimate,
                expand: 'relation_multi', filter: "id = '${mainItem['id']}'")
            .getSingleOrNull();
        expect(result, isNotNull);
        expect(result!['plain_text'], 'main_ultimate_multi_single_val');
        expect(result['expand'], isNotNull);
        expect(result['expand']['relation_multi'], isNotNull);

        final expandedRelations = result['expand']['relation_multi'] as List;
        expect(expandedRelations.length, 1);
        expect(expandedRelations[0]['name'], 'multi_related_single_val');
        expect(expandedRelations[0]['id'], relatedItem1['id']);
      });

      test('multi relation with no related items (empty list)', () async {
        final mainItem = await db.$create(ultimate, {
          'plain_text': 'main_ultimate_multi_empty',
          'relation_multi': [], // Empty list
        });

        final result = await db
            .$query(ultimate,
                expand: 'relation_multi', filter: "id = '${mainItem['id']}'")
            .getSingleOrNull();
        expect(result, isNotNull);
        expect(result!['plain_text'], 'main_ultimate_multi_empty');
        expect(result['expand'], isNotNull);
        expect(result['expand']['relation_multi'], isNotNull);
        expect(result['expand']['relation_multi'].length, 0);
      });

      test('multi relation with null value (should be treated as empty)',
          () async {
        final mainItem = await db.$create(ultimate, {
          'plain_text': 'main_ultimate_multi_null',
          'relation_multi': null, // Null value
        });

        final result = await db
            .$query(ultimate,
                expand: 'relation_multi', filter: "id = '${mainItem['id']}'")
            .getSingleOrNull();
        expect(result, isNotNull);
        expect(result!['plain_text'], 'main_ultimate_multi_null');
        expect(result['expand'], isNotNull);
        expect(result['expand']['relation_multi'], isNotNull);
        expect(result['expand']['relation_multi'].length, 0);
      });

      test('N+1 check: expanding multiple items with shared relations',
          () async {
        final relatedItem1 =
            await db.$create(todo, {'name': 'related_shared_1'});
        final relatedItem2 =
            await db.$create(todo, {'name': 'related_shared_2'});
        final relatedItem3 =
            await db.$create(todo, {'name': 'related_shared_3'});

        await db.$create(ultimate, {
          'plain_text': 'main_for_n+1_A',
          'relation_multi': [relatedItem1['id'], relatedItem2['id']],
        });
        await db.$create(ultimate, {
          'plain_text': 'main_for_n+1_B',
          'relation_multi': [relatedItem2['id'], relatedItem3['id']],
        });

        final results = await db
            .$query(ultimate,
                filter: "plain_text ~ '%main_for_n+1%'",
                expand: 'relation_multi')
            .get();

        expect(results.length, 2);

        final itemA =
            results.firstWhere((r) => r['plain_text'] == 'main_for_n+1_A');
        final itemB =
            results.firstWhere((r) => r['plain_text'] == 'main_for_n+1_B');

        final expandA = itemA['expand']['relation_multi'] as List;
        final expandB = itemB['expand']['relation_multi'] as List;

        expect(expandA.length, 2);
        expect(expandB.length, 2);

        expect(expandA.any((r) => r['id'] == relatedItem1['id']), isTrue);
        expect(expandA.any((r) => r['id'] == relatedItem2['id']), isTrue);

        expect(expandB.any((r) => r['id'] == relatedItem2['id']), isTrue);
        expect(expandB.any((r) => r['id'] == relatedItem3['id']), isTrue);
      });
    });
  });
}
