import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase_drift/src/database/database.dart';

void main() {
  final connection = DatabaseConnection(NativeDatabase.memory());
  final db = DataBase(connection);

  group('collections', () {
    test('empty', () async {
      final items = await db.collectionsDao.getAll();

      expect(items.length, 0);
    });

    test('create', () async {
      final id = await db.collectionsDao.createCollection(
        name: 'Test 123',
      );

      final items = await db.collectionsDao.getAll();

      expect(id.isNotEmpty, true);
      expect(items.length, 1);

      await db.collectionsDao.deleteCollection(id: id);
    });

    test('update', () async {
      final id = await db.collectionsDao.createCollection(
        name: 'Test 123',
      );

      final items = await db.collectionsDao.getAll();

      expect(id.isNotEmpty, true);
      expect(items.length, 1);

      await db.collectionsDao.updateCollection(
        id: id,
        name: 'Test 1234',
      );

      final item = await db.collectionsDao.getCollectionById(id);

      expect(item?.name, 'Test 1234');

      await db.collectionsDao.deleteCollection(id: id);
    });

    test('delete', () async {
      final id = await db.collectionsDao.createCollection(
        name: 'Test 123',
      );

      final items = await db.collectionsDao.getAll();

      expect(id.isNotEmpty, true);
      expect(items.length, 1);

      await db.collectionsDao.deleteCollection(id: id);

      final items2 = await db.collectionsDao.getAll();

      expect(items2.length, 0);
    });
  });

  group('records', () {
    test('empty', () async {
      final items = await db.recordsDao.getAll();

      expect(items.length, 0);
    });

    test('create', () async {
      final collectionId = await db.collectionsDao.createCollection(
        name: 'Test 123',
      );
      final collection = await db //
          .collectionsDao
          .getCollectionById(collectionId);

      final id = await db.recordsDao.createRecord(
        collection: collection!,
        id: null,
        data: {
          'name': 'Test 456',
        },
      );

      expect(id.isNotEmpty, true);

      final item = await db.recordsDao.getRecord(
        collectionId: collectionId,
        id: id,
      );

      expect(item?.data['name'], 'Test 456');

      final items = await db.recordsDao.getAll(collectionId: collectionId);

      expect(items.length, 1);

      await db.recordsDao.deleteRecord(id: id, collectionId: collectionId);
      await db.collectionsDao.deleteCollection(id: collectionId);
    });

    test('update', () async {
      final collectionId = await db.collectionsDao.createCollection(
        name: 'Test 123',
      );
      final collection = await db //
          .collectionsDao
          .getCollectionById(collectionId);

      final id = await db.recordsDao.createRecord(
        collection: collection!,
        id: null,
        data: {
          'name': 'Test 456',
        },
      );

      expect(id.isNotEmpty, true);

      final item = await db.recordsDao.getRecord(
        collectionId: collectionId,
        id: id,
      );

      expect(item?.data['name'], 'Test 456');

      await db.recordsDao.updateRecord(
        id: id,
        collection: collection,
        data: {
          'name': 'Test 789',
        },
      );

      final item2 = await db.recordsDao.getRecord(
        collectionId: collectionId,
        id: id,
      );

      expect(item2?.data['name'], 'Test 789');

      await db.recordsDao.deleteRecord(id: id, collectionId: collectionId);
      await db.collectionsDao.deleteCollection(id: collectionId);
    });

    test('delete', () async {
      final collectionId = await db.collectionsDao.createCollection(
        name: 'Test 123',
      );
      final collection = await db //
          .collectionsDao
          .getCollectionById(collectionId);

      final id = await db.recordsDao.createRecord(
        collection: collection!,
        id: null,
        data: {
          'name': 'Test 456',
        },
      );

      expect(id.isNotEmpty, true);

      final item = await db.recordsDao.getRecord(
        collectionId: collectionId,
        id: id,
      );

      expect(item?.data['name'], 'Test 456');

      await db.recordsDao.deleteRecord(id: id, collectionId: collectionId);

      final item2 = await db.recordsDao.getRecord(
        collectionId: collectionId,
        id: id,
      );

      expect(item2, null);

      await db.collectionsDao.deleteCollection(id: collectionId);
    });
  });
}
