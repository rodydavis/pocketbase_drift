import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pocketbase_drift/pocketbase_drift.dart';

import 'support.dart';

/// Offline changes reaching the server intact.
void syncCorrectnessTests() {
  group('sync correctness', () {
    test(
        'P9 an offline edit of a record with server files does not re-upload them',
        () async {
      final c = await clients.create();
      final post = await c.collection('posts').create(
        body: {'title': uniq('P9')},
        files: [
          http.MultipartFile.fromBytes('cover', tinyPng, filename: 'cover.png')
        ],
      );
      final coverBefore =
          (await Lab.record('posts', post.id))!['cover'] as String;
      expect(coverBefore, isNotEmpty);

      c.connectivity.setConnectivityStatus(false);
      final renamed = uniq('P9 renamed');
      await c.collection('posts').update(post.id, body: {'title': renamed});
      final pending =
          (await c.db.pendingRecords(service: 'posts').get()).single;
      expect(pending.data[RecordMeta.pendingFields], isNot(contains('cover')));
      expect(pending.data[RecordMeta.pendingFiles], anyOf(isNull, isEmpty));

      c.connectivity.setConnectivityStatus(true);
      await c.syncPendingChanges();

      final server = (await Lab.record('posts', post.id))!;
      expect(server['title'], renamed);
      expect(server['cover'], coverBefore,
          reason: 'file must not be re-uploaded');
      expect(await pendingIds(c, 'posts'), isEmpty);
    });

    test(
        'P10 sync sends only the locally changed fields; other devices\' changes survive',
        () async {
      final c = await clients.create();
      final id = (await Lab.create(
              'posts', {'title': uniq('P10'), 'likes': 1, 'body': 'v1'}))['id']
          as String;
      await c.collection('posts').getOne(id);

      c.connectivity.setConnectivityStatus(false);
      final mine = uniq('P10 offline title');
      await c.collection('posts').update(id, body: {'title': mine});
      final pending =
          (await c.db.pendingRecords(service: 'posts').get()).single;
      expect(pending.data[RecordMeta.pendingFields], ['title']);

      await Lab.mutate(
          'posts', id, {'likes': 999, 'body': 'edited by device B'});
      c.connectivity.setConnectivityStatus(true);
      await c.syncPendingChanges();

      final server = (await Lab.record('posts', id))!;
      expect(server['title'], mine);
      expect(server['likes'], 999);
      expect(server['body'], 'edited by device B');
      final local = await c
          .collection('posts')
          .getOne(id, requestPolicy: RequestPolicy.cacheOnly);
      expect(local.data[RecordMeta.synced], isTrue);
      expect(local.get<int>('likes'), 999);
    });

    test(
        'P11b a list refresh keeps a pending offline edit; after sync the server has it',
        () async {
      final c = await clients.create();
      final id =
          (await Lab.create('posts', {'title': uniq('P11b'), 'likes': 3}))['id']
              as String;
      await c.collection('posts').getOne(id);

      // The server is reachable; only this record's endpoint fails once.
      await Lab.chaos('fail503', match: '/api/collections/posts/records/$id');
      final edit = uniq('P11b pending edit');
      await c.collection('posts').update(id, body: {'title': edit});
      expect(await pendingIds(c, 'posts'), [id]);
      await Lab.calm();

      await Lab.mutate('posts', id, {'likes': 4}); // another device, later
      final page =
          await c.collection('posts').getList(sort: '-updated', perPage: 20);
      expect(page.items.map((r) => r.id), contains(id));

      final local = await c
          .collection('posts')
          .getOne(id, requestPolicy: RequestPolicy.cacheOnly);
      expect(local.get<String>('title'), edit);
      expect(local.get<int>('likes'), 4, reason: 'server fields merge in');
      expect(await pendingIds(c, 'posts'), [id]);

      await c.syncPendingChanges();
      final server = (await Lab.record('posts', id))!;
      expect(server['title'], edit);
      expect(server['likes'], 4);
      expect(await pendingIds(c, 'posts'), isEmpty);
    });

    test(
        'P7 a queued create the server rejects is kept with syncError, reported on syncFailures and discardable',
        () async {
      final c = await clients.create(localSyncRetryCount: 1);
      final failures = <SyncFailure>[];
      final sub = c.syncFailures.listen(failures.add);
      addTearDown(sub.cancel);

      c.connectivity.setConnectivityStatus(false);
      final rejected =
          await c.collection('posts').create(body: {'title': 'z' * 120});
      c.connectivity.setConnectivityStatus(true);
      await c.syncPendingChanges();

      await eventually(() => failures.isNotEmpty,
          reason: 'a SyncFailure is emitted');
      final failure = failures.single;
      expect(failure.collection, 'posts');
      expect(failure.recordId, rejected.id);
      expect(failure.operation, SyncOperation.create);
      expect(failure.statusCode, 400);
      expect(failure.dropped, isFalse);

      final parked = (await c.db.pendingRecords(service: 'posts').get()).single;
      expect(parked.id, rejected.id);
      expect(parked.data[RecordMeta.syncError], isNotNull);

      // Automatic sync skips it; an explicit retry includes it.
      await c.syncPendingChanges();
      expect(failures, hasLength(1));
      await c.syncPendingChanges(includeFailed: true);
      await eventually(() => failures.length == 2,
          reason: 'the retry is reported');

      await c.discardPendingChange('posts', rejected.id);
      expect(await pendingIds(c, 'posts'), isEmpty);
      expect(
        await c
            .collection('posts')
            .getOneOrNull(rejected.id, requestPolicy: RequestPolicy.cacheOnly),
        isNull,
      );
      expect(await Lab.record('posts', rejected.id), isNull);
    });

    test(
        'P8 a queued update of a record deleted on the server is dropped and reported (dropped: true)',
        () async {
      final c = await clients.create();
      final failures = <SyncFailure>[];
      final sub = c.syncFailures.listen(failures.add);
      addTearDown(sub.cancel);
      final id =
          (await Lab.create('posts', {'title': uniq('P8 sync 404')}))['id']
              as String;
      await c.collection('posts').getOne(id);

      c.connectivity.setConnectivityStatus(false);
      await c.collection('posts').update(id, body: {'likes': 5});
      await Lab.delete('posts', id);
      c.connectivity.setConnectivityStatus(true);
      await c.syncPendingChanges();

      await eventually(() => failures.isNotEmpty,
          reason: 'a SyncFailure is emitted');
      expect(failures.single.recordId, id);
      expect(failures.single.operation, SyncOperation.update);
      expect(failures.single.dropped, isTrue);
      expect(await Lab.record('posts', id), isNull, reason: 'never recreated');
      expect(
        await c
            .collection('posts')
            .getOneOrNull(id, requestPolicy: RequestPolicy.cacheOnly),
        isNull,
      );
    });

    test('P31 a write right after an un-awaited setSchema waits for the schema',
        () async {
      final schema = jsonEncode(await serverSchema());
      final c = clients.track($PocketBase.database(
        baseUrl,
        connection: DatabaseConnection(NativeDatabase.memory()),
        authStore: $AuthStore(save: (_) async {}),
      ));
      unawaited(c.setSchema(schema));
      final title = uniq('P31');

      final record = await c.collection('tasks').create(
          body: {'title': title}, requestPolicy: RequestPolicy.cacheOnly);

      expect(record.get<String>('title'), title);
      final local = await c.collection('tasks').getFullList(
          filter: 'title = "$title"', requestPolicy: RequestPolicy.cacheOnly);
      expect(local.map((r) => r.id), [record.id]);
    });

    test(
        'P32 authStore.clear() keeps pending changes, hidden from other accounts, and they sync after the same account logs in',
        () async {
      final c = await clients.create();
      final title = uniq('P32');
      c.connectivity.setConnectivityStatus(false);
      final queued = await c.collection('tasks').create(body: {'title': title});
      expect(await pendingIds(c, 'tasks'), [queued.id]);

      c.authStore.clear(); // e.g. the token expired while offline
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(await pendingIds(c, 'tasks'), isEmpty,
          reason: 'hidden while logged out');
      final kept = await c.db
          .$query('tasks',
              filter: 'id = "${queued.id}"', includeOtherOwners: true)
          .get();
      expect(kept, hasLength(1), reason: 'the pending row is kept');

      c.connectivity.setConnectivityStatus(true);
      await c.collection('users').authWithPassword(lab2Email, labPassword);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await c.syncCompleted;
      expect(await pendingIds(c, 'tasks'), isEmpty,
          reason: 'hidden from another account');
      expect(await Lab.record('tasks', queued.id), isNull,
          reason: 'another account must not sync it');

      c.authStore.clear();
      await c.collection('users').authWithPassword(labEmail, labPassword);
      await eventually(() async => await Lab.record('tasks', queued.id) != null,
          reason: 'the pending create syncs after the owner logs in again');
      await c.syncCompleted;
      expect((await Lab.record('tasks', queued.id))!['title'], title);
      await eventually(() async => (await pendingIds(c, 'tasks')).isEmpty,
          reason: 'nothing left pending');
    });

    test(
        'queued modifier edits sync as deltas: another device\'s increment and upload survive',
        () async {
      final c = await clients.create();
      final post = await c.collection('posts').create(
        body: {'title': uniq('delta'), 'likes': 1},
        files: [
          http.MultipartFile.fromBytes('images', tinyPng, filename: 'one.png'),
          http.MultipartFile.fromBytes('images', tinyPng, filename: 'two.png'),
        ],
      );
      final before = ((await Lab.record('posts', post.id))!['images'] as List)
          .cast<String>();
      expect(before, hasLength(2));

      c.connectivity.setConnectivityStatus(false);
      await c.collection('posts').update(
        post.id,
        body: {
          'likes+': 2,
          'images-': [before.first],
        },
        files: [
          http.MultipartFile.fromBytes('images+', tinyPng, filename: 'mine.png')
        ],
      );
      await c.collection('posts').update(post.id, body: {'likes-': 1});

      // Another device, while this one is offline.
      await (await admin()).collection('posts').update(
        post.id,
        body: {'likes+': 5},
        files: [
          http.MultipartFile.fromBytes('images+', tinyPng,
              filename: 'theirs.png')
        ],
      );

      c.connectivity.setConnectivityStatus(true);
      await c.syncPendingChanges();

      final server = (await Lab.record('posts', post.id))!;
      expect(server['likes'], 7, reason: '1 + 5 (other device) + 2 - 1');
      final images = (server['images'] as List).cast<String>();
      expect(images, hasLength(3));
      expect(images, isNot(contains(before.first)));
      expect(images, contains(before.last));
      expect(images.where((n) => n.startsWith('theirs')), hasLength(1));
      expect(images.where((n) => n.startsWith('mine')), hasLength(1));

      final local = await c
          .collection('posts')
          .getOne(post.id, requestPolicy: RequestPolicy.cacheOnly);
      expect(local.data[RecordMeta.synced], isTrue);
      expect(local.get<num>('likes'), 7);
      expect(local.get<List<dynamic>>('images'), images);
      expect(await pendingIds(c, 'posts'), isEmpty);
    });
  });
}
