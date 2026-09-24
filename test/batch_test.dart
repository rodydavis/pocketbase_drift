import 'dart:io' as io;
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase_drift/pocketbase_drift.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  io.HttpOverrides.global = null;

  late $PocketBase client;

  setUpAll(() async {
    // Mock the connectivity plugin
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('dev.fluttercommunity.plus/connectivity'),
            (MethodCall methodCall) async => ['wifi']);

    client = $PocketBase.database(
      'http://127.0.0.1:8090',
      connection: DatabaseConnection(NativeDatabase.memory()),
    );

    // Set up schema for test collections
    await client.db.setSchema([
      {
        'id': 'posts_collection',
        'name': 'posts',
        'type': 'base',
        'fields': [
          {'name': 'title', 'type': 'text', 'required': true},
          {'name': 'content', 'type': 'text', 'required': false},
          {'name': 'published', 'type': 'bool', 'required': false},
        ],
      },
      {
        'id': 'comments_collection',
        'name': 'comments',
        'type': 'base',
        'fields': [
          {'name': 'text', 'type': 'text', 'required': true},
          {'name': 'post_id', 'type': 'text', 'required': false},
        ],
      },
      {
        'id': 'tags_collection',
        'name': 'tags',
        'type': 'base',
        'fields': [
          {'name': 'name', 'type': 'text', 'required': true},
        ],
      },
    ]);
  });

  tearDownAll(() async {
    await client.db.close();
  });

  group('Batch Service - Initialization', () {
    test('\$createBatch returns a \$BatchService instance', () {
      final batch = client.$createBatch();
      expect(batch, isA<$BatchService>());
    });

    test('batch starts empty', () {
      final batch = client.$createBatch();
      expect(batch.isEmpty, true);
      expect(batch.length, 0);
    });

    test('collection returns same \$SubBatchService for same collection', () {
      final batch = client.$createBatch();
      final posts1 = batch.collection('posts');
      final posts2 = batch.collection('posts');
      expect(identical(posts1, posts2), true);
    });

    test(
        'collection returns different \$SubBatchService for different collections',
        () {
      final batch = client.$createBatch();
      final posts = batch.collection('posts');
      final comments = batch.collection('comments');
      expect(identical(posts, comments), false);
    });
  });

  group('Batch Service - Queuing Operations', () {
    test('create operation is queued', () {
      final batch = client.$createBatch();
      batch.collection('posts').create(body: {'title': 'Test Post'});
      expect(batch.length, 1);
    });

    test('update operation is queued', () {
      final batch = client.$createBatch();
      batch.collection('posts').update('abc123', body: {'title': 'Updated'});
      expect(batch.length, 1);
    });

    test('delete operation is queued', () {
      final batch = client.$createBatch();
      batch.collection('posts').delete('abc123');
      expect(batch.length, 1);
    });

    test('upsert operation is queued', () {
      final batch = client.$createBatch();
      batch
          .collection('posts')
          .upsert(body: {'id': 'abc123', 'title': 'Upserted'});
      expect(batch.length, 1);
    });

    test('multiple operations across collections are queued', () {
      final batch = client.$createBatch();

      batch.collection('posts').create(body: {'title': 'New Post'});
      batch
          .collection('posts')
          .update('post1', body: {'title': 'Updated Post'});
      batch.collection('comments').create(body: {'text': 'New Comment'});
      batch.collection('tags').delete('tag1');

      expect(batch.length, 4);
    });
  });

  group('Batch Service - Cache Only Send', () {
    setUp(() async {
      // Clear all collections before each test
      await client.db.deleteAll('posts');
      await client.db.deleteAll('comments');
      await client.db.deleteAll('tags');
    });

    test('cacheOnly creates records in local cache', () async {
      final batch = client.$createBatch();

      batch.collection('posts').create(body: {'title': 'Cached Post'});
      batch.collection('comments').create(body: {'text': 'Cached Comment'});

      final results = await batch.send(requestPolicy: RequestPolicy.cacheOnly);

      expect(results.length, 2);
      expect(results[0].isSuccess, true);
      expect(results[1].isSuccess, true);

      // Verify records are in cache
      final posts = await client.db.$query('posts').get();
      final comments = await client.db.$query('comments').get();

      expect(posts.length, 1);
      expect(posts.first['title'], 'Cached Post');
      expect(comments.length, 1);
      expect(comments.first['text'], 'Cached Comment');
    });

    test('cacheOnly marks records as noSync', () async {
      final batch = client.$createBatch();
      batch.collection('posts').create(body: {'title': 'Local Only Post'});

      await batch.send(requestPolicy: RequestPolicy.cacheOnly);

      final posts = await client.db.$query('posts').get();
      expect(posts.first['noSync'], true);
      expect(posts.first['synced'], false);
    });

    test('cacheOnly update modifies existing record', () async {
      // Create initial record
      await client.db.$create('posts', {
        'id': 'existing_post',
        'title': 'Original Title',
        'synced': true,
      });

      final batch = client.$createBatch();
      batch
          .collection('posts')
          .update('existing_post', body: {'title': 'Updated Title'});

      final results = await batch.send(requestPolicy: RequestPolicy.cacheOnly);

      expect(results.first.isSuccess, true);

      final posts =
          await client.db.$query('posts', filter: "id = 'existing_post'").get();
      expect(posts.first['title'], 'Updated Title');
    });

    test('cacheOnly delete marks record as deleted', () async {
      // Create record to delete
      await client.db.$create('posts', {
        'id': 'delete_me',
        'title': 'To Be Deleted',
        'synced': true,
      });

      final batch = client.$createBatch();
      batch.collection('posts').delete('delete_me');

      final results = await batch.send(requestPolicy: RequestPolicy.cacheOnly);

      expect(results.first.status, 204);

      // Record should be marked as deleted
      final posts = await client.db
          .$query('posts', filter: "id = 'delete_me'", includeDeleted: true)
          .get();
      expect(posts.first['deleted'], true);
    });

    test('cacheOnly upsert creates new record when ID does not exist',
        () async {
      final batch = client.$createBatch();
      batch
          .collection('posts')
          .upsert(body: {'id': 'new_upsert', 'title': 'New via Upsert'});

      await batch.send(requestPolicy: RequestPolicy.cacheOnly);

      final posts =
          await client.db.$query('posts', filter: "id = 'new_upsert'").get();
      expect(posts.length, 1);
      expect(posts.first['title'], 'New via Upsert');
      expect(posts.first['isNew'], true);
    });

    test('cacheOnly upsert updates existing record when ID exists', () async {
      // Create existing record
      await client.db.$create('posts', {
        'id': 'existing_upsert',
        'title': 'Original',
        'synced': true,
      });

      final batch = client.$createBatch();
      batch.collection('posts').upsert(
          body: {'id': 'existing_upsert', 'title': 'Updated via Upsert'});

      await batch.send(requestPolicy: RequestPolicy.cacheOnly);

      final posts = await client.db
          .$query('posts', filter: "id = 'existing_upsert'")
          .get();
      expect(posts.length, 1);
      expect(posts.first['title'], 'Updated via Upsert');
      expect(posts.first['isNew'], false);
    });
  });

  group('Batch Service - Result Handling', () {
    setUp(() async {
      await client.db.deleteAll('posts');
      await client.db.deleteAll('comments');
    });

    test('results include collection information', () async {
      final batch = client.$createBatch();
      batch.collection('posts').create(body: {'title': 'Test'});
      batch.collection('comments').create(body: {'text': 'Test'});

      final results = await batch.send(requestPolicy: RequestPolicy.cacheOnly);

      expect(results[0].collection, 'posts');
      expect(results[1].collection, 'comments');
    });

    test('results include record ID for create operations', () async {
      final batch = client.$createBatch();
      batch.collection('posts').create(body: {'title': 'Test'});

      final results = await batch.send(requestPolicy: RequestPolicy.cacheOnly);

      expect(results.first.recordId, isNotNull);
      expect(results.first.recordId!.length, 15); // PocketBase ID format
    });

    test('results include record ID for update operations', () async {
      await client.db.$create(
          'posts', {'id': 'update_test', 'title': 'Original', 'synced': true});

      final batch = client.$createBatch();
      batch
          .collection('posts')
          .update('update_test', body: {'title': 'Updated'});

      final results = await batch.send(requestPolicy: RequestPolicy.cacheOnly);

      expect(results.first.recordId, 'update_test');
    });

    test('record getter returns RecordModel from successful result', () async {
      final batch = client.$createBatch();
      batch.collection('posts').create(body: {'title': 'Record Model Test'});

      final results = await batch.send(requestPolicy: RequestPolicy.cacheOnly);

      final record = results.first.record;
      expect(record, isNotNull);
      expect(record, isA<RecordModel>());
      expect(record!.data['title'], 'Record Model Test');
    });

    test('isSuccess returns true for 2xx status codes', () async {
      final batch = client.$createBatch();
      batch.collection('posts').create(body: {'title': 'Success Test'});

      final results = await batch.send(requestPolicy: RequestPolicy.cacheOnly);

      expect(results.first.isSuccess, true);
      expect(results.first.isError, false);
      expect(results.first.status, 201);
    });
  });

  group('Batch Service - Empty Batch', () {
    test('sending empty batch returns empty results', () async {
      final batch = client.$createBatch();

      final results = await batch.send(requestPolicy: RequestPolicy.cacheOnly);

      expect(results, isEmpty);
    });
  });

  group('Batch Service - Mixed Operations', () {
    setUp(() async {
      await client.db.deleteAll('posts');
      await client.db.deleteAll('comments');
      await client.db.deleteAll('tags');
    });

    test('batch with create, update, and delete operations', () async {
      // Setup: create records to update and delete
      await client.db.$create(
          'posts', {'id': 'to_update', 'title': 'Original', 'synced': true});
      await client.db.$create(
          'comments', {'id': 'to_delete', 'text': 'Delete me', 'synced': true});

      final batch = client.$createBatch();

      // Create new post
      batch.collection('posts').create(body: {'title': 'New Post'});

      // Update existing post
      batch
          .collection('posts')
          .update('to_update', body: {'title': 'Updated Post'});

      // Delete comment
      batch.collection('comments').delete('to_delete');

      // Create new tag
      batch.collection('tags').create(body: {'name': 'flutter'});

      final results = await batch.send(requestPolicy: RequestPolicy.cacheOnly);

      expect(results.length, 4);
      expect(results.every((r) => r.isSuccess || r.status == 204), true);

      // Verify final state
      final posts = await client.db.$query('posts').get();
      final comments = await client.db
          .$query('comments', includeDeleted: true)
          .get();
      final tags = await client.db.$query('tags').get();

      expect(posts.length, 2); // Original + new
      expect(posts.firstWhere((p) => p['id'] == 'to_update')['title'],
          'Updated Post');
      expect(comments.first['deleted'], true); // Marked as deleted
      expect(tags.length, 1);
      expect(tags.first['name'], 'flutter');
    });

    test('batch preserves order of operations in results', () async {
      final batch = client.$createBatch();

      batch.collection('posts').create(body: {'title': 'First'});
      batch.collection('comments').create(body: {'text': 'Second'});
      batch.collection('tags').create(body: {'name': 'Third'});
      batch.collection('posts').create(body: {'title': 'Fourth'});

      final results = await batch.send(requestPolicy: RequestPolicy.cacheOnly);

      expect(results.length, 4);
      expect(results[0].collection, 'posts');
      expect(results[1].collection, 'comments');
      expect(results[2].collection, 'tags');
      expect(results[3].collection, 'posts');
    });
  });

  group('\$BatchResult', () {
    test('toString includes key information', () async {
      final batch = client.$createBatch();
      batch.collection('posts').create(body: {'title': 'Test'});

      final results = await batch.send(requestPolicy: RequestPolicy.cacheOnly);

      final str = results.first.toString();
      expect(str, contains('posts'));
      expect(str, contains('201'));
    });
  });
}
