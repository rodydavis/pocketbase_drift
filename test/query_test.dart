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

  setUpAll(() async {
    for (final collection in collections) {
      await db.collectionsDao.createItem(collection);
    }
  });

  group('query builder', () {
    test('empty', () async {
      final statement = db.queryBuilder('todo');

      expect(statement.isNotEmpty, true);
      expect(statement, 'SELECT * FROM records WHERE collectionName = "todo"');
    });

    test('fields', () async {
      final statement = db.queryBuilder(
        'todo',
        fields: 'id, created',
      );

      expect(statement.isNotEmpty, true);
      expect(statement,
          'SELECT id, created FROM records WHERE collectionName = "todo"');
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
          'SELECT * FROM records WHERE collectionName = "todo" ORDER BY created DESC, id ASC');
      expect(statement2.isNotEmpty, true);
      expect(statement2,
          'SELECT * FROM records WHERE collectionName = "todo" ORDER BY created ASC, id ASC');
      expect(statement3.isNotEmpty, true);
      expect(statement3,
          'SELECT * FROM records WHERE collectionName = "todo" ORDER BY date ASC');
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
          'SELECT id, created FROM records WHERE collectionName = "todo" AND (id = "1234") ORDER BY created DESC, id ASC');
    });

    test('json_extract', () {
      final statement = db.queryBuilder(
        'todo',
        fields: 'id, name',
      );

      expect(statement.isNotEmpty, true);
      expect(statement,
          'SELECT id, json_extract(records.data, \'\$.name\') as name FROM records WHERE collectionName = "todo"');
    });
  });
  group('query test', () {
    test('empty if no data', () async {
      final result = await db.$query(todoCollection, fields: 'id, name').get();

      expect(result, []);
    });

    test('single result', () async {
      final newItem = await db.recordsDao.createItem(Record(
        id: db.generateId(),
        metadata: {},
        created: DateTime.now(),
        updated: DateTime.now(),
        data: {
          'name': 'test',
        },
        collectionId: todoCollection.id,
        collectionName: todoCollection.name,
      ));

      final result = await db
          .$query(
            todoCollection,
            fields: 'id, name',
          )
          .getSingleOrNull();
      final resultData = result;

      expect(resultData != null, true);
      expect(resultData!['name'], 'test');
      expect(resultData['id'], newItem);

      await db.recordsDao.deleteItem(newItem);
    });

    test('multiple results', () async {
      final newItem1 = await db.recordsDao.createItem(Record(
        id: db.generateId(),
        metadata: {},
        created: DateTime.now(),
        updated: DateTime.now(),
        data: {
          'name': 'test1',
        },
        collectionId: todoCollection.id,
        collectionName: todoCollection.name,
      ));
      final newItem2 = await db.recordsDao.createItem(Record(
        id: db.generateId(),
        metadata: {},
        created: DateTime.now(),
        updated: DateTime.now(),
        data: {
          'name': 'test2',
        },
        collectionId: todoCollection.id,
        collectionName: todoCollection.name,
      ));

      final result = await db.$query(todoCollection, fields: 'id, name').get();

      expect(result.length, 2);
      expect(result[0]['name'], 'test1');
      expect(result[0]['id'], newItem1);
      expect(result[1]['name'], 'test2');
      expect(result[1]['id'], newItem2);

      await db.recordsDao.deleteItem(newItem1);
      await db.recordsDao.deleteItem(newItem2);
    });

    test('query multiple results', () async {
      final newItem1 = await db.recordsDao.createItem(Record(
        id: db.generateId(),
        metadata: {},
        created: DateTime.now(),
        updated: DateTime.now(),
        data: {
          'name': 'test1',
        },
        collectionId: todoCollection.id,
        collectionName: todoCollection.name,
      ));
      final newItem2 = await db.recordsDao.createItem(Record(
        id: db.generateId(),
        metadata: {},
        created: DateTime.now(),
        updated: DateTime.now(),
        data: {
          'name': 'test2',
        },
        collectionId: todoCollection.id,
        collectionName: todoCollection.name,
      ));

      final result = await db
          .$query(todoCollection, fields: 'id, name', filter: 'name = "test1"')
          .get();

      expect(result.length, 1);
      expect(result[0]['name'], 'test1');
      expect(result[0]['id'], newItem1);

      await db.recordsDao.deleteItem(newItem1);
      await db.recordsDao.deleteItem(newItem2);
    });

    test('select fields', () async {
      final newItem1 = await db.recordsDao.createItem(Record(
        id: db.generateId(),
        metadata: {},
        created: DateTime.now(),
        updated: DateTime.now(),
        data: {
          'name': 'test1',
        },
        collectionId: todoCollection.id,
        collectionName: todoCollection.name,
      ));

      final result = await db
          .$query(todoCollection, fields: 'name', filter: 'name = "test1"')
          .get();

      expect(result.length, 1);
      expect(result[0]['name'], 'test1');
      expect(result[0].keys.length, 1);

      await db.recordsDao.deleteItem(newItem1);
    });

    test('correct order', () async {
      final newItem1 = await db.recordsDao.createItem(Record(
        id: db.generateId(),
        metadata: {},
        created: DateTime.now(),
        updated: DateTime.now(),
        data: {
          'name': 'test1',
        },
        collectionId: todoCollection.id,
        collectionName: todoCollection.name,
      ));
      final newItem2 = await db.recordsDao.createItem(Record(
        id: db.generateId(),
        metadata: {},
        created: DateTime.now().add(const Duration(seconds: 1)),
        updated: DateTime.now().add(const Duration(seconds: 1)),
        data: {
          'name': 'test2',
        },
        collectionId: todoCollection.id,
        collectionName: todoCollection.name,
      ));

      final result = await db
          .$query(
            todoCollection,
            fields: 'id, name',
            sort: 'created',
          )
          .get();

      expect(result.length, 2);
      expect(result[0]['name'], 'test1');
      expect(result[0]['id'], newItem1);
      expect(result[1]['name'], 'test2');
      expect(result[1]['id'], newItem2);

      await db.recordsDao.deleteItem(newItem1);
      await db.recordsDao.deleteItem(newItem2);
    });

    group('expand tests', () {
      test('single relation', () async {
        final mCol = collections.firstWhere((e) => e.name == 'ultimate');
        final tCol = collections.firstWhere((e) => e.name == 'todo');

        final newItem1 = await db.recordsDao.createItem(Record(
          id: db.generateId(),
          metadata: {},
          created: DateTime.now(),
          updated: DateTime.now(),
          data: {
            'name': 'test1',
          },
          collectionId: tCol.id,
          collectionName: tCol.name,
        ));
        final newItem2 = await db.recordsDao.createItem(Record(
          id: db.generateId(),
          metadata: {},
          created: DateTime.now(),
          updated: DateTime.now(),
          data: {
            'plain_text': 'test2',
            'relation_single': newItem1,
          },
          collectionId: mCol.id,
          collectionName: mCol.name,
        ));

        final result = await db
            .$query(
              mCol,
              expand: 'relation_single',
            )
            .get();

        final data = result[0];

        expect(data['plain_text'], 'test2');
        expect(data['id'], newItem2);
        expect(data['expand']['relation_single'][0]['name'], 'test1');

        await db.recordsDao.deleteItem(newItem1);
        await db.recordsDao.deleteItem(newItem2);
      });

      test('multi relation', () async {
        final mCol = collections.firstWhere((e) => e.name == 'ultimate');
        final tCol = collections.firstWhere((e) => e.name == 'todo');

        final newItem1 = await db.recordsDao.createItem(Record(
          id: db.generateId(),
          metadata: {},
          created: DateTime.now(),
          updated: DateTime.now(),
          data: {
            'name': 'test1',
          },
          collectionId: tCol.id,
          collectionName: tCol.name,
        ));
        final newItem2 = await db.recordsDao.createItem(Record(
          id: db.generateId(),
          metadata: {},
          created: DateTime.now(),
          updated: DateTime.now(),
          data: {
            'plain_text': 'test2',
            'relation_multi': newItem1,
          },
          collectionId: mCol.id,
          collectionName: mCol.name,
        ));

        final result = await db
            .$query(
              mCol,
              expand: 'relation_multi',
            )
            .get();

        final data = result[0];

        expect(data['plain_text'], 'test2');
        expect(data['id'], newItem2);
        expect(data['expand']['relation_multi'][0]['name'], 'test1');

        await db.recordsDao.deleteItem(newItem1);
        await db.recordsDao.deleteItem(newItem2);
      });
    });
  });
}
