import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pocketbase_drift/pocketbase_drift.dart';

void main() {
  final connection = DatabaseConnection(NativeDatabase.memory());
  final db = DataBase(connection);

  group('collections', () {
    test('empty', () async {
      final items = await db.collectionsDao.getAll();

      expect(items.length, 0);
    });

    test('create', () async {
      final id = await db.collectionsDao.createItem(CollectionModel(
        name: 'Test 123',
      ).toModel(
        deleted: false,
        synced: null,
      ));

      final items = await db.collectionsDao.getAll();

      expect(id.isNotEmpty, true);
      expect(items.length, 1);

      await db.collectionsDao.deleteItem(id);
    });

    test('update', () async {
      final id = await db.collectionsDao.createItem(CollectionModel(
        name: 'Test 123',
      ).toModel(
        deleted: false,
        synced: null,
      ));

      final items = await db.collectionsDao.getAll();

      expect(id.isNotEmpty, true);
      expect(items.length, 1);

      await db.collectionsDao.updateItem(CollectionModel(
        id: id,
        name: 'Test 1234',
      ).toModel(
        deleted: false,
        synced: null,
      ));

      final item = await db.collectionsDao.get(id);

      expect(item?.name, 'Test 1234');

      await db.collectionsDao.deleteItem(id);
    });

    test('delete', () async {
      final id = await db.collectionsDao.createItem(CollectionModel(
        name: 'Test 123',
      ).toModel(
        deleted: false,
        synced: null,
      ));

      final items = await db.collectionsDao.getAll();

      expect(id.isNotEmpty, true);
      expect(items.length, 1);

      await db.collectionsDao.deleteItem(id);

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
      final collectionId = await db.collectionsDao.createItem(CollectionModel(
        name: 'Test 123',
      ).toModel(
        deleted: false,
        synced: null,
      ));
      final collection = await db //
          .collectionsDao
          .get(collectionId);

      final id = await db.recordsDao.createItem(RecordModel(
        collectionId: collection!.id,
        collectionName: collection.name,
        data: {
          'name': 'Test 456',
        },
      ).toModel(
        deleted: false,
        synced: false,
      ));

      expect(id.isNotEmpty, true);

      final item = await db.recordsDao.get(
        id,
        collection: collectionId,
      );

      expect(item?.data['name'], 'Test 456');

      final items = await db.recordsDao.getAll(collection: collectionId);

      expect(items.length, 1);

      await db.recordsDao.deleteItem(id, collection: collectionId);
      await db.collectionsDao.deleteItem(collectionId);
    });

    test('update', () async {
      final collectionId = await db.collectionsDao.createItem(CollectionModel(
        name: 'Test 123',
      ).toModel(
        deleted: false,
        synced: null,
      ));
      final collection = await db //
          .collectionsDao
          .get(collectionId);

      final id = await db.recordsDao.createItem(
        RecordModel(
          collectionId: collection!.id,
          collectionName: collection.name,
          data: {
            'name': 'Test 456',
          },
        ).toModel(
          deleted: false,
          synced: false,
        ),
      );

      expect(id.isNotEmpty, true);

      final item = await db.recordsDao.get(
        id,
        collection: collectionId,
      );

      expect(item?.data['name'], 'Test 456');

      await db.recordsDao.updateItem(RecordModel(
        id: id,
        collectionId: collection.id,
        collectionName: collection.name,
        data: {
          'name': 'Test 789',
        },
      ).toModel(
        deleted: false,
        synced: false,
      ));

      final item2 = await db.recordsDao.get(
        id,
        collection: collectionId,
      );

      expect(item2?.data['name'], 'Test 789');

      await db.recordsDao.deleteItem(id, collection: collectionId);
      await db.collectionsDao.deleteItem(collectionId);
    });

    test('delete', () async {
      final collectionId = await db.collectionsDao.createItem(CollectionModel(
        name: 'Test 123',
      ).toModel(
        deleted: false,
        synced: null,
      ));
      final collection = await db //
          .collectionsDao
          .get(collectionId);

      final id = await db.recordsDao.createItem(
        RecordModel(
          collectionId: collection!.id,
          collectionName: collection.name,
          data: {
            'name': 'Test 456',
          },
        ).toModel(
          deleted: false,
          synced: false,
        ),
      );

      expect(id.isNotEmpty, true);

      final item = await db.recordsDao.get(
        id,
        collection: collectionId,
      );

      expect(item?.data['name'], 'Test 456');

      await db.recordsDao.deleteItem(id, collection: collectionId);

      final item2 = await db.recordsDao.get(
        id,
        collection: collectionId,
      );

      expect(item2, null);

      await db.collectionsDao.deleteItem(collectionId);
    });
  });
}
