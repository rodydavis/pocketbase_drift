import 'dart:io' as io;
import 'package:drift/drift.dart';
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

    // Set up schema for a 'posts' collection
    await client.db.setSchema([
      {
        'id': 'posts_collection',
        'name': 'posts',
        'type': 'base',
        'fields': [
          {'name': 'title', 'type': 'text', 'required': true},
          {'name': 'community', 'type': 'text', 'required': false},
          {'name': 'author', 'type': 'text', 'required': false},
        ],
      },
    ]);
  });

  tearDownAll(() async {
    await client.db.close();
  });

  group('syncLocal - Filter-Aware Deletion', () {
    setUp(() async {
      // Clear all posts before each test
      await client.db.deleteAll('posts');
    });

    test('syncLocal without filter deletes records not in server response',
        () async {
      // Arrange: Create some local records
      await client.db.$create('posts', {
        'id': 'post1',
        'title': 'Post 1',
        'synced': true,
      });
      await client.db.$create('posts', {
        'id': 'post2',
        'title': 'Post 2',
        'synced': true,
      });
      await client.db.$create('posts', {
        'id': 'post3',
        'title': 'Post 3',
        'synced': true,
      });

      // Verify we have 3 local records
      var localPosts = await client.db.$query('posts').get();
      expect(localPosts.length, 3);

      // Act: Sync with server response that only includes post1 and post2
      // (post3 was "deleted" on the server)
      await client.db.syncLocal('posts', [
        {
          'id': 'post1',
          'title': 'Post 1 Updated',
          'updated': DateTime.now().toIso8601String()
        },
        {
          'id': 'post2',
          'title': 'Post 2',
          'updated': DateTime.now().toIso8601String()
        },
      ]);

      // Assert: post3 should be deleted
      localPosts = await client.db.$query('posts').get();
      expect(localPosts.length, 2);
      expect(localPosts.map((p) => p['id']).toList(),
          containsAll(['post1', 'post2']));
      expect(localPosts.map((p) => p['id']).toList(), isNot(contains('post3')));
    });

    test(
        'syncLocal with filter only deletes filtered records not in server response',
        () async {
      // Arrange: Create posts in different communities
      await client.db.$create('posts', {
        'id': 'post_communityA_1',
        'title': 'Community A Post 1',
        'community': 'communityA',
        'synced': true,
      });
      await client.db.$create('posts', {
        'id': 'post_communityA_2',
        'title': 'Community A Post 2 (will be deleted on server)',
        'community': 'communityA',
        'synced': true,
      });
      await client.db.$create('posts', {
        'id': 'post_communityB_1',
        'title': 'Community B Post 1',
        'community': 'communityB',
        'synced': true,
      });
      await client.db.$create('posts', {
        'id': 'post_communityB_2',
        'title': 'Community B Post 2',
        'community': 'communityB',
        'synced': true,
      });

      // Verify we have 4 local records
      var localPosts = await client.db.$query('posts').get();
      expect(localPosts.length, 4);

      // Act: Sync with server response for communityA that only includes post1
      // (post_communityA_2 was "deleted" on the server for communityA)
      await client.db.syncLocal(
        'posts',
        [
          {
            'id': 'post_communityA_1',
            'title': 'Community A Post 1',
            'community': 'communityA',
            'updated': DateTime.now().toIso8601String(),
          },
        ],
        filter: "community = 'communityA'",
      );

      // Assert:
      // - post_communityA_2 should be deleted (was in filter scope, not in server response)
      // - post_communityB_1 and post_communityB_2 should still exist (outside filter scope)
      localPosts = await client.db.$query('posts').get();
      expect(localPosts.length, 3, reason: 'Should have 3 posts after sync');

      final postIds = localPosts.map((p) => p['id']).toList();
      expect(postIds, contains('post_communityA_1'),
          reason: 'Should keep synced post');
      expect(postIds, isNot(contains('post_communityA_2')),
          reason: 'Should delete missing post from communityA');
      expect(postIds, contains('post_communityB_1'),
          reason: 'Should keep post from communityB');
      expect(postIds, contains('post_communityB_2'),
          reason: 'Should keep post from communityB');
    });

    test('syncLocal preserves unsynced local records', () async {
      // Arrange: Create a synced record and an unsynced record
      await client.db.$create('posts', {
        'id': 'synced_post',
        'title': 'Synced Post',
        'synced': true,
      });
      await client.db.$create('posts', {
        'id': 'unsynced_post',
        'title': 'Unsynced Post (created offline)',
        'synced': false,
        'isNew': true,
      });

      // Act: Sync with empty server response
      await client.db.syncLocal('posts', []);

      // Assert: The unsynced post should still exist
      final localPosts = await client.db.$query('posts').get();
      expect(localPosts.length, 1);
      expect(localPosts.first['id'], 'unsynced_post');
    });

    test('syncLocal preserves local-only records (noSync=true)', () async {
      // Arrange: Create a synced record and a local-only record
      await client.db.$create('posts', {
        'id': 'synced_post',
        'title': 'Synced Post',
        'synced': true,
      });
      await client.db.$create('posts', {
        'id': 'local_only_post',
        'title': 'Local Only Post',
        'synced': true, // Even if marked synced
        'noSync': true, // It's local-only
      });

      // Act: Sync with empty server response
      await client.db.syncLocal('posts', []);

      // Assert: The local-only post should still exist
      final localPosts = await client.db.$query('posts').get();
      expect(localPosts.length, 1);
      expect(localPosts.first['id'], 'local_only_post');
    });

    test('syncLocal preserves pending deletion records (deleted=true)',
        () async {
      // Arrange: Create a synced record and a pending-delete record
      await client.db.$create('posts', {
        'id': 'synced_post',
        'title': 'Synced Post',
        'synced': true,
      });
      await client.db.$create('posts', {
        'id': 'pending_delete_post',
        'title': 'Pending Delete Post',
        'synced': true,
        'deleted': true, // Marked for deletion, will be synced by retry
      });

      // Act: Sync with empty server response
      await client.db.syncLocal('posts', []);

      // Assert: The pending-delete post should still exist (will be handled
      // by retry), but only visible when explicitly including tombstones.
      final tombstones = await client.db
          .$query('posts', includeDeleted: true)
          .get();
      expect(tombstones.length, 1);
      expect(tombstones.first['id'], 'pending_delete_post');

      // Regular reads must not surface the tombstone.
      final localPosts = await client.db.$query('posts').get();
      expect(localPosts, isEmpty);
    });

    test(
        'syncLocal safety: does not mass-delete when server returns empty with many local records',
        () async {
      // Arrange: Create more than 10 local records (the safety threshold)
      for (var i = 0; i < 15; i++) {
        await client.db.$create('posts', {
          'id': 'post_$i',
          'title': 'Post $i',
          'synced': true,
        });
      }

      // Verify we have 15 local records
      var localPosts = await client.db.$query('posts').get();
      expect(localPosts.length, 15);

      // Act: Sync with empty server response
      // This simulates a server error or empty collection
      await client.db.syncLocal('posts', []);

      // Assert: Safety check should prevent mass deletion
      // All 15 records should still exist
      localPosts = await client.db.$query('posts').get();
      expect(localPosts.length, 15,
          reason:
              'Safety check should prevent deleting all records when server returns empty');
    });

    test('syncLocal correctly handles mixed scenario with filter', () async {
      // Arrange: Real-world scenario with posts by different authors
      await client.db.$create('posts', {
        'id': 'alice_post1',
        'title': 'Alice Post 1',
        'author': 'alice',
        'synced': true,
      });
      await client.db.$create('posts', {
        'id': 'alice_post2_deleted',
        'title': 'Alice Post 2 (deleted on server)',
        'author': 'alice',
        'synced': true,
      });
      await client.db.$create('posts', {
        'id': 'bob_post1',
        'title': 'Bob Post 1',
        'author': 'bob',
        'synced': true,
      });
      // This is a post Alice is drafting offline
      await client.db.$create('posts', {
        'id': 'alice_draft',
        'title': 'Alice Draft (not synced yet)',
        'author': 'alice',
        'synced': false,
        'isNew': true,
      });

      // Act: Sync Alice's posts from server (alice_post2 was deleted)
      await client.db.syncLocal(
        'posts',
        [
          {
            'id': 'alice_post1',
            'title': 'Alice Post 1',
            'author': 'alice',
            'updated': DateTime.now().toIso8601String(),
          },
        ],
        filter: "author = 'alice'",
      );

      // Assert:
      // - alice_post1 should exist (in server response)
      // - alice_post2_deleted should be deleted (in filter scope, not in server response)
      // - bob_post1 should exist (outside filter scope)
      // - alice_draft should exist (unsynced, preserved)
      final localPosts = await client.db.$query('posts').get();
      expect(localPosts.length, 3);

      final postIds = localPosts.map((p) => p['id']).toSet();
      expect(postIds, contains('alice_post1'));
      expect(postIds, isNot(contains('alice_post2_deleted')));
      expect(postIds, contains('bob_post1'));
      expect(postIds, contains('alice_draft'));
    });
  });
}
