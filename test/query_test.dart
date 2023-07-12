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

  setUpAll(() async {
    await db.setSchema(collections.map((e) => e.toJson()).toList());
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

  group('query builder', () {
    test('empty', () async {
      final statement = db.queryBuilder('todo');

      expect(statement.isNotEmpty, true);
      expect(statement, 'SELECT * FROM services WHERE service = \'todo\'');
    });

    test('fields', () async {
      final statement = db.queryBuilder(
        'todo',
        fields: 'id, created',
      );
      final statement2 = db.queryBuilder(
        'todo',
        fields: 'id, name',
      );

      expect(statement.isNotEmpty, true);
      expect(statement2.isNotEmpty, true);
      expect(
          statement, 'SELECT id, created FROM services WHERE service = \'todo\'');
      expect(statement2,
          "SELECT id, json_extract(services.data, '\$.name') as name FROM services WHERE service = 'todo'");
    });

    test('sort', () async {
      final statement1 = db.queryBuilder(
        'todo',
        sort: '-created,id',
      );
      final statement2 = db.queryBuilder(
        'todo',
        sort: '+created,id',
      );
      final statement3 = db.queryBuilder(
        'todo',
        sort: 'date',
      );

      expect(statement1.isNotEmpty, true);
      expect(statement1,
          'SELECT * FROM services WHERE service = \'todo\' ORDER BY created DESC, id ASC');
      expect(statement2.isNotEmpty, true);
      expect(statement2,
          'SELECT * FROM services WHERE service = \'todo\' ORDER BY created ASC, id ASC');
      expect(statement3.isNotEmpty, true);
      expect(statement3,
          'SELECT * FROM services WHERE service = \'todo\' ORDER BY date ASC');
    });

    test('all', () async {
      final statement = db.queryBuilder(
        'todo',
        sort: '-created,id',
        fields: 'id, created',
        filter: 'id = "1234"',
      );

      expect(statement.isNotEmpty, true);
      expect(statement,
          'SELECT id, created FROM services WHERE service = \'todo\' AND (id = "1234") ORDER BY created DESC, id ASC');
    });

    test('string multi split', () {
      expect(
        'name = "todo" AND data != true OR id = ""'.multiSplit([
          ' AND ',
          ' OR ',
        ]),
        [
          'name = "todo"',
          'data != true',
          'id = ""',
        ],
      );
    });

    test('json_extract fields', () {
      final statement = db.queryBuilder(
        'todo',
        fields: 'id, name',
      );

      expect(statement.isNotEmpty, true);
      expect(statement,
          'SELECT id, json_extract(services.data, \'\$.name\') as name FROM services WHERE service = \'todo\'');
    });

    test('json_extract filter', () {
      final statement = db.queryBuilder(
        'todo',
        filter: 'name = "test1"',
      );

      expect(statement.isNotEmpty, true);
      expect(statement,
          'SELECT * FROM services WHERE service = \'todo\' AND (json_extract(services.data, \'\$.name\') = "test1")');
    });
  });
  group('query test', () {
    test('empty if no data', () async {
      final result = await db.$query(todo, fields: 'id, name').get();

      expect(result, []);
    });

    test('single result', () async {
      final newItem = await db.$create(
        todo,
        RecordModel(
          id: db.generateId(),
          created: DateTime.now().toIso8601String(),
          updated: DateTime.now().toIso8601String(),
          data: {
            'name': 'test',
          },
          collectionId: todoCollection.id,
          collectionName: todoCollection.name,
        ).toJson(),
      );

      final result = await db
          .$query(
            todo,
            fields: 'id, name',
          )
          .getSingleOrNull();
      final resultData = result;

      expect(resultData != null, true);
      expect(resultData!['name'], 'test');
      expect(resultData['id'], newItem['id']);

      await db.$delete(todo, newItem['id']);
    });

    test('multiple results', () async {
      final newItem1 = await db.$create(
        todo,
        RecordModel(
          id: db.generateId(),
          created: DateTime.now().toIso8601String(),
          updated: DateTime.now().toIso8601String(),
          data: {
            'name': 'test1',
          },
          collectionId: todoCollection.id,
          collectionName: todoCollection.name,
        ).toJson(),
      );
      final newItem2 = await db.$create(
        todo,
        RecordModel(
          id: db.generateId(),
          created: DateTime.now().toIso8601String(),
          updated: DateTime.now().toIso8601String(),
          data: {
            'name': 'test2',
          },
          collectionId: todoCollection.id,
          collectionName: todoCollection.name,
        ).toJson(),
      );

      final result = await db.$query(todo, fields: 'id, name').get();

      expect(result.length, 2);
      expect(result[0]['name'], 'test1');
      expect(result[0]['id'], newItem1['id']);
      expect(result[1]['name'], 'test2');
      expect(result[1]['id'], newItem2['id']);

      await db.$delete(todo, newItem1['id']);
      await db.$delete(todo, newItem2['id']);
    });

    test('query multiple results', () async {
      final newItem1 = await db.$create(
        todo,
        RecordModel(
          id: db.generateId(),
          created: DateTime.now().toIso8601String(),
          updated: DateTime.now().toIso8601String(),
          data: {
            'name': 'test1',
          },
          collectionId: todoCollection.id,
          collectionName: todoCollection.name,
        ).toJson(),
      );
      final newItem2 = await db.$create(
        todo,
        RecordModel(
          id: db.generateId(),
          created: DateTime.now().toIso8601String(),
          updated: DateTime.now().toIso8601String(),
          data: {
            'name': 'test2',
          },
          collectionId: todoCollection.id,
          collectionName: todoCollection.name,
        ).toJson(),
      );

      final result = await db
          .$query(todo, fields: 'id, name', filter: 'name = \'test1\'')
          .get();

      expect(result.length, 1);
      expect(result[0]['name'], 'test1');
      expect(result[0]['id'], newItem1['id']);

      await db.$delete(todo, newItem1['id']);
      await db.$delete(todo, newItem2['id']);
    });

    test('select fields', () async {
      final newItem1 = await db.$create(
        todo,
        RecordModel(
          id: db.generateId(),
          created: DateTime.now().toIso8601String(),
          updated: DateTime.now().toIso8601String(),
          data: {
            'name': 'test1',
          },
          collectionId: todoCollection.id,
          collectionName: todoCollection.name,
        ).toJson(),
      );

      final result =
          await db.$query(todo, fields: 'name', filter: 'name = \'test1\'').get();

      expect(result.length, 1);
      expect(result[0]['name'], 'test1');
      expect(result[0].keys.length, 1);

      await db.$delete(todo, newItem1['id']);
    });

    test('correct order', () async {
      final newItem1 = await db.$create(
        todo,
        RecordModel(
          id: db.generateId(),
          created: DateTime.now().toIso8601String(),
          updated: DateTime.now().toIso8601String(),
          data: {
            'name': 'test1',
          },
          collectionId: todoCollection.id,
          collectionName: todoCollection.name,
        ).toJson(),
      );
      final newItem2 = await db.$create(
        todo,
        RecordModel(
          id: db.generateId(),
          created: DateTime.now().toIso8601String(),
          updated: DateTime.now().toIso8601String(),
          data: {
            'name': 'test2',
          },
          collectionId: todoCollection.id,
          collectionName: todoCollection.name,
        ).toJson(),
      );

      final result = await db
          .$query(
            todo,
            fields: 'id, name',
            sort: 'created',
          )
          .get();

      expect(result.length, 2);
      expect(result[0]['name'], 'test1');
      expect(result[0]['id'], newItem1['id']);
      expect(result[1]['name'], 'test2');
      expect(result[1]['id'], newItem2['id']);

      await db.$delete(todo, newItem1['id']);
      await db.$delete(todo, newItem2['id']);
    });

    group('expand tests', () {
      test('single relation', () async {
        final mCol = collections.firstWhere((e) => e.name == 'ultimate');
        final tCol = collections.firstWhere((e) => e.name == 'todo');

        final newItem1 = await db.$create(tCol.name, {
          'name': 'test1',
        });
        final newItem2 = await db.$create(mCol.name, {
          'plain_text': 'test2',
          'relation_single': newItem1['id'],
        });

        final result = await db
            .$query(
              mCol.name,
              expand: 'relation_single',
            )
            .get();

        final data = result[0];

        expect(data['plain_text'], 'test2');
        expect(data['id'], newItem2['id']);
        expect(data['expand']['relation_single'][0]['name'], 'test1');

        await db.$delete(tCol.name, newItem1['id']);
        await db.$delete(mCol.name, newItem2['id']);
      });

      test('multi relation', () async {
        final mCol = collections.firstWhere((e) => e.name == 'ultimate');
        final tCol = collections.firstWhere((e) => e.name == 'todo');

        final newItem1 = await db.$create(tCol.name, {
          'name': 'test1',
        });
        final newItem2 = await db.$create(mCol.name, {
          'plain_text': 'test2',
          'relation_multi': newItem1['id'],
        });

        final result = await db
            .$query(
              mCol.name,
              expand: 'relation_multi',
            )
            .get();

        final data = result[0];

        expect(data['plain_text'], 'test2');
        expect(data['id'], newItem2['id']);
        expect(data['expand']['relation_multi'][0]['name'], 'test1');

        await db.$delete(tCol.name, newItem1['id']);
        await db.$delete(mCol.name, newItem2['id']);
      });
    });
  });
}
