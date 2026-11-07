import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pocketbase_drift/pocketbase_drift.dart';

import 'test_data/collections.json.dart';

/// Tests for PocketBase SDK's `RecordModel.get<T>()` dot-notation path access
/// for locally expanded relations.
///
/// The PocketBase SDK uses dot-notation to access nested fields:
/// - `record.get<String>('expand.user.name')` - single relation (direct access)
/// - `record.get<RecordModel>('expand.user')` - single relation as RecordModel
/// - `record.get<List<RecordModel>>('expand.products')` - multi relation as list
/// - `record.get<int>('expand.items.0.quantity')` - multi relation by index
///
/// These tests verify that local expansion in pocketbase_drift produces
/// data structures compatible with this API, matching the official SDK behavior:
/// - Single relations (maxSelect == 1): returned as object directly
/// - Multi relations (maxSelect > 1): returned as list

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

  group('Single relation expand (maxSelect == 1)', () {
    test('access field directly via expand.<relation>.<field>', () async {
      // Setup: Create a related record and a main record
      final relatedItem = await db.$create(todo, {'name': 'Test Todo Item'});
      final mainItem = await db.$create(ultimate, {
        'plain_text': 'Main Record',
        'relation_single': relatedItem['id'],
      });

      // Query with expansion
      final result = await db
          .$query(ultimate,
              expand: 'relation_single', filter: "id = '${mainItem['id']}'")
          .getSingleOrNull();

      expect(result, isNotNull);

      // Convert to RecordModel (simulating what the service layer does)
      final record = RecordModel.fromJson(result!);

      // Test: Access using PocketBase SDK dot-notation API (no index needed for single)
      expect(
        record.get<String>('expand.relation_single.name'),
        'Test Todo Item',
        reason: 'Single relation should be accessible directly without index',
      );

      // Test: Access the expanded record directly as RecordModel
      final expandedRecord = record.get<RecordModel>('expand.relation_single');
      expect(expandedRecord, isNotNull);
      expect(expandedRecord.get<String>('name'), 'Test Todo Item');

      // Test: Access ID of the expanded record
      expect(
        record.get<String>('expand.relation_single.id'),
        relatedItem['id'],
      );
    });

    test('nested single relation - access deeply nested field directly',
        () async {
      // Setup: user -> todo -> ultimate (3 levels, all single relations)
      final user = await db.$create(users, {'name': 'John Doe'});
      final todoItem = await db.$create(todo, {
        'name': 'Todo with User',
        'user': user['id'],
      });
      final mainItem = await db.$create(ultimate, {
        'plain_text': 'Ultimate with Nested',
        'relation_single': todoItem['id'],
      });

      // Query with nested expansion
      final result = await db
          .$query(ultimate,
              expand: 'relation_single.user',
              filter: "id = '${mainItem['id']}'")
          .getSingleOrNull();

      expect(result, isNotNull);
      final record = RecordModel.fromJson(result!);

      // Test: Access first-level expanded field (single relation - no index)
      expect(
        record.get<String>('expand.relation_single.name'),
        'Todo with User',
      );

      // Test: Access second-level (nested) expanded field (single relation - no index)
      expect(
        record.get<String>('expand.relation_single.expand.user.name'),
        'John Doe',
        reason: 'Nested single relations should also be accessible directly',
      );

      // Test: Get the nested RecordModel directly
      final nestedUser =
          record.get<RecordModel>('expand.relation_single.expand.user');
      expect(nestedUser, isNotNull);
      expect(nestedUser.get<String>('name'), 'John Doe');
    });

    test('null single relation - returns null', () async {
      final mainItem = await db.$create(ultimate, {
        'plain_text': 'Null Relation',
        'relation_single': null,
      });

      final result = await db
          .$query(ultimate,
              expand: 'relation_single', filter: "id = '${mainItem['id']}'")
          .getSingleOrNull();

      expect(result, isNotNull);
      final record = RecordModel.fromJson(result!);

      // Test: Single relation with null value should return null
      final expandedRecord =
          record.get<RecordModel?>('expand.relation_single', null);
      expect(expandedRecord, isNull);

      // Test: Accessing nested field with default value
      expect(
        record.get<String>('expand.relation_single.name', 'default'),
        'default',
      );
    });
  });

  group('Multi relation expand (maxSelect > 1)', () {
    test('access items by index', () async {
      // Setup: multiple related records
      final related1 = await db.$create(todo, {'name': 'First Todo'});
      final related2 = await db.$create(todo, {'name': 'Second Todo'});
      final related3 = await db.$create(todo, {'name': 'Third Todo'});

      final mainItem = await db.$create(ultimate, {
        'plain_text': 'Multi Relation Test',
        'relation_multi': [related1['id'], related2['id'], related3['id']],
      });

      // Query with expansion
      final result = await db
          .$query(ultimate,
              expand: 'relation_multi', filter: "id = '${mainItem['id']}'")
          .getSingleOrNull();

      expect(result, isNotNull);
      final record = RecordModel.fromJson(result!);

      // Test: Access as list
      final expandedList =
          record.get<List<RecordModel>>('expand.relation_multi');
      expect(expandedList.length, 3);

      // Test: Access by index (multi relations require index)
      expect(record.get<String>('expand.relation_multi.0.name'), isNotEmpty);
      expect(record.get<String>('expand.relation_multi.1.name'), isNotEmpty);
      expect(record.get<String>('expand.relation_multi.2.name'), isNotEmpty);

      // Verify all names are present
      final names = expandedList.map((r) => r.get<String>('name')).toList();
      expect(names, containsAll(['First Todo', 'Second Todo', 'Third Todo']));
    });

    test('empty multi relation - returns empty list', () async {
      final mainItem = await db.$create(ultimate, {
        'plain_text': 'No Relations',
        'relation_multi': [],
      });

      final result = await db
          .$query(ultimate,
              expand: 'relation_multi', filter: "id = '${mainItem['id']}'")
          .getSingleOrNull();

      expect(result, isNotNull);
      final record = RecordModel.fromJson(result!);

      // Test: Get the empty list
      final expandedList =
          record.get<List<RecordModel>>('expand.relation_multi');
      expect(expandedList, isEmpty);

      // Test: Accessing non-existent index with default value
      expect(
        record.get<String>('expand.relation_multi.0.name', 'N/A'),
        'N/A',
        reason: 'Should return default value for non-existent index',
      );
    });
  });

  group('Mixed single and multi relation expand', () {
    test('both relation types in same record', () async {
      // Setup: Create related records
      final singleRelated = await db.$create(todo, {'name': 'Single Related'});
      final multiRelated1 = await db.$create(todo, {'name': 'Multi 1'});
      final multiRelated2 = await db.$create(todo, {'name': 'Multi 2'});

      final mainItem = await db.$create(ultimate, {
        'plain_text': 'Mixed Relations',
        'relation_single': singleRelated['id'],
        'relation_multi': [multiRelated1['id'], multiRelated2['id']],
      });

      // Query with both expansions
      final result = await db
          .$query(ultimate,
              expand: 'relation_single,relation_multi',
              filter: "id = '${mainItem['id']}'")
          .getSingleOrNull();

      expect(result, isNotNull);
      final record = RecordModel.fromJson(result!);

      // Test: Single relation - direct access (no index)
      expect(
        record.get<String>('expand.relation_single.name'),
        'Single Related',
      );

      // Test: Multi relation - access by index
      expect(record.get<String>('expand.relation_multi.0.name'), isNotEmpty);
      expect(record.get<String>('expand.relation_multi.1.name'), isNotEmpty);

      // Test: Get types correctly
      final singleRecord = record.get<RecordModel>('expand.relation_single');
      expect(singleRecord, isNotNull);

      final multiList = record.get<List<RecordModel>>('expand.relation_multi');
      expect(multiList.length, 2);
    });

    test('mixed data types in expanded record', () async {
      final todoItem = await db.$create(todo, {'name': 'Type Test'});
      final mainItem = await db.$create(ultimate, {
        'plain_text': 'Type Test Main',
        'number': 42.5,
        'bool': true,
        'email': 'test@example.com',
        'relation_single': todoItem['id'],
      });

      final result = await db
          .$query(ultimate,
              expand: 'relation_single', filter: "id = '${mainItem['id']}'")
          .getSingleOrNull();

      expect(result, isNotNull);
      final record = RecordModel.fromJson(result!);

      // Test: Access various types on the main record
      expect(record.get<String>('plain_text'), 'Type Test Main');
      expect(record.get<double>('number'), 42.5);
      expect(record.get<bool>('bool'), true);
      expect(record.get<String>('email'), 'test@example.com');

      // Test: Access single expanded record (no index)
      expect(record.get<String>('expand.relation_single.name'), 'Type Test');
    });
  });

  group('Direct field access vs expand path equivalence', () {
    test('same ID accessible via relation field and expand path', () async {
      final user = await db.$create(users, {'name': 'Path Test User'});
      final todoItem = await db.$create(todo, {
        'name': 'Path Test Todo',
        'user': user['id'],
      });

      // Get the todo with user expanded
      final result = await db
          .$query(todo, expand: 'user', filter: "id = '${todoItem['id']}'")
          .getSingleOrNull();

      expect(result, isNotNull);
      final record = RecordModel.fromJson(result!);

      // Access user ID directly from the relation field
      expect(record.get<String>('user'), user['id']);

      // Access user name via expand path (single relation - no index)
      expect(record.get<String>('expand.user.name'), 'Path Test User');

      // Access user ID via expand path (should match direct access)
      expect(
        record.get<String>('expand.user.id'),
        record.get<String>('user'),
      );
    });
  });
}
