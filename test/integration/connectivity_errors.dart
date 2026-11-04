import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase_drift/pocketbase_drift.dart';

import 'support.dart';

/// Connectivity state, error surfacing and write queueing.
void connectivityErrorTests() {
  group('connectivity and errors', () {
    test(
        'P5a each statusStream listener gets only the current status and no sync pass starts',
        () async {
      final c = await clients.create();
      // Let the passes started by the client start and the login finish.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await c.syncCompleted;
      final logs = LogTap();
      addTearDown(logs.close);

      final existing = <bool>[];
      final existingSub = c.connectivity.statusStream.listen(existing.add);
      addTearDown(existingSub.cancel);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(existing, [true]);

      for (var i = 0; i < 5; i++) {
        final got = <bool>[];
        final sub = c.connectivity.statusStream.listen(got.add);
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await sub.cancel();
        expect(got, [true], reason: 'listener $i gets only the current status');
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(existing, [true], reason: 'other listeners see no re-emit');
      expect(
        logs.count('Syncing pending changes') +
            logs.count('No pending changes to sync') +
            logs.count('Starting retry for'),
        0,
        reason: 'listening must not start a sync pass: ${logs.lines}',
      );
    });

    test('P5b syncCompleted completes when sync passes overlap (calls join)',
        () async {
      final c = await clients.create();
      final title = uniq('P5b');
      c.connectivity.setConnectivityStatus(false);
      final queued = await c.collection('tasks').create(body: {'title': title});
      expect(await pendingIds(c, 'tasks'), [queued.id]);

      await Lab.chaos('latency',
          match: '/api/collections/tasks/records', latencyMs: 1500);
      c.connectivity.setConnectivityStatus(true); // starts a sync pass
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final first = c.syncCompleted;
      final listener = c.connectivity.statusStream.listen((_) {});
      addTearDown(listener.cancel);
      final joined = c.syncPendingChanges();
      final joinedFailed = c.syncPendingChanges(includeFailed: true);

      await Future.wait([first, joined, joinedFailed])
          .timeout(const Duration(seconds: 20));
      await c.syncCompleted.timeout(const Duration(seconds: 5));

      expect(await pendingIds(c, 'tasks'), isEmpty);
      final onServer = await serverRecords('tasks', 'title = "$title"');
      expect(onServer.map((r) => r.id), [queued.id]);
    });

    test(
        'P6 4xx answers keep the client online and surface as ClientException with the status',
        () async {
      final c = await clients.create();
      final posts = c.collection('posts');

      for (var i = 0; i < 2; i++) {
        final e = await clientError(() => posts.getOne('doesnotexist123',
            requestPolicy: RequestPolicy.networkOnly));
        expect(e.statusCode, 404);
      }
      expect(c.connectivity.isConnected, isTrue);

      final uncached = await clientError(() => posts.getOne('doesnotexist456'));
      expect(uncached.statusCode, 404);

      final forbidden =
          await clientError(() => c.collection('locked').getList());
      expect(forbidden.statusCode, 403);

      final badFilter = await clientError(() => posts.getList(
          filter: 'title ==== nope', requestPolicy: RequestPolicy.networkOnly));
      expect(badFilter.statusCode, 400);

      expect(c.connectivity.isConnected, isTrue);
      expect(c.connectivity.canReachServer, isTrue);
    });

    test(
        'P7 cacheAndNetwork create rejected with 400/403 throws and stores or queues nothing',
        () async {
      final c = await clients.create();
      final tooLong = 'x' * 120; // posts.title max is 80

      final e400 = await clientError(
          () => c.collection('posts').create(body: {'title': tooLong}));
      expect(e400.statusCode, 400);

      final lockedTitle = uniq('P7 locked');
      final e403 = await clientError(
          () => c.collection('locked').create(body: {'title': lockedTitle}));
      expect(e403.statusCode, 403);

      expect(await c.db.pendingRecords().get(), isEmpty);
      expect(
        await c.collection('posts').getFullList(
            filter: 'title = "$tooLong"',
            requestPolicy: RequestPolicy.cacheOnly),
        isEmpty,
      );
      expect(
        await c
            .collection('locked')
            .getFullList(requestPolicy: RequestPolicy.cacheOnly),
        isEmpty,
      );
      expect(c.connectivity.isConnected, isTrue);
    });

    test(
        'P7 cacheAndNetwork create queues the write only when the server is unreachable (503, dropped connection)',
        () async {
      final c = await clients.create();
      final posts = c.collection('posts');

      await Lab.chaos('fail503', match: '/api/collections/posts/records');
      final a = await posts.create(body: {'title': uniq('P7 503')});
      await Lab.chaos('drop', match: '/api/collections/posts/records');
      final b = await posts.create(body: {'title': uniq('P7 drop')});

      expect(a.data[RecordMeta.synced], isFalse);
      expect(b.data[RecordMeta.synced], isFalse);
      expect(await pendingIds(c, 'posts'), unorderedEquals([a.id, b.id]));

      await Lab.calm();
      c.connectivity.setConnectivityStatus(true);
      await c.syncPendingChanges();

      expect(await pendingIds(c, 'posts'), isEmpty);
      expect(
          (await Lab.record('posts', a.id))?['title'], a.get<String>('title'));
      expect(
          (await Lab.record('posts', b.id))?['title'], b.get<String>('title'));
    });

    test(
        'P8 networkFirst update answered 400 throws and does not fall back to a create',
        () async {
      final c = await clients.create();
      final title = uniq('P8 400');
      final id = (await Lab.create('posts', {'title': title, 'likes': 1}))['id']
          as String;
      await c.collection('posts').getOne(id);

      final e = await clientError(() => c.collection('posts').update(id,
          body: {'title': 'y' * 120},
          requestPolicy: RequestPolicy.networkFirst));
      expect(e.statusCode, 400);

      expect((await Lab.record('posts', id))?['title'], title);
      expect(await c.db.pendingRecords().get(), isEmpty);
      expect(c.connectivity.isConnected, isTrue);
    });

    test(
        'P8 networkFirst update answered 404 throws, never recreates the record and drops the stale copy',
        () async {
      final c = await clients.create();
      final id = (await Lab.create('posts', {
        'title': uniq('P8 404'),
        'likes': 7,
        'body': 'original body'
      }))['id'] as String;
      await c.collection('posts').getOne(id);
      await Lab.delete('posts', id); // another device deletes it

      final e = await clientError(() => c.collection('posts').update(id,
          body: {'likes': 8}, requestPolicy: RequestPolicy.networkFirst));
      expect(e.statusCode, 404);

      expect(await Lab.record('posts', id), isNull,
          reason: 'must not be recreated');
      expect(
        await c
            .collection('posts')
            .getOneOrNull(id, requestPolicy: RequestPolicy.cacheOnly),
        isNull,
      );
      expect(await c.db.pendingRecords().get(), isEmpty);
    });

    test(
        'P17 cacheFirst getOne on a cold cache while online returns the server record',
        () async {
      final c = await clients.create();
      final title = uniq('P17');
      final id = (await Lab.create('posts', {'title': title}))['id'] as String;

      final record = await c
          .collection('posts')
          .getOne(id, requestPolicy: RequestPolicy.cacheFirst);

      expect(record.id, id);
      expect(record.get<String>('title'), title);
    });

    test('cacheOnly getOne of an uncached record throws CacheMissException',
        () async {
      final c = await clients.create();
      await expectLater(
        c
            .collection('posts')
            .getOne('notcached12345', requestPolicy: RequestPolicy.cacheOnly),
        throwsA(isA<CacheMissException>()),
      );
    });

    test(
        'P23 a hung server does not block a cacheAndNetwork write beyond requestTimeout; the write is queued',
        () async {
      final c =
          await clients.create(requestTimeout: const Duration(seconds: 2));
      final title = uniq('P23');
      await Lab.chaos('hang', match: '/api/collections/tasks/records');

      final record = await c
          .collection('tasks')
          .create(body: {'title': title}).timeout(const Duration(seconds: 10),
              onTimeout: () => fail('create still blocked after 10 s'));

      expect(record.data[RecordMeta.synced], isFalse);
      expect(await pendingIds(c, 'tasks'), [record.id]);

      await Lab.calm();
      c.connectivity.setConnectivityStatus(true);
      await c.syncPendingChanges();
      expect((await Lab.record('tasks', record.id))?['title'], title);
    });

    final reads = <String, Future<Object?> Function($RecordService posts)>{
      'getOne': (posts) => posts.getOne('doesnotexist789'),
      'getList': (posts) => posts.getList(),
      'getFullList': (posts) => posts.getFullList(),
      'getFirstListItem': (posts) =>
          posts.getFirstListItem('title = "Post 001"'),
    };
    for (final read in reads.entries) {
      test(
          'P34 dropped connections mark the client offline after the failure threshold (${read.key})',
          () async {
        final c = await clients.create();
        await Lab.chaos('drop', match: '/api/collections/posts/records');
        for (var i = 0; i < 2; i++) {
          // Lists fall back to the (empty) cache; single reads throw.
          try {
            await read.value(c.collection('posts'));
          } on ClientException catch (e) {
            expect(e.statusCode, 0, reason: 'unreachable server');
          }
        }
        expect(c.connectivity.isConnected, isFalse);
      });
    }

    test(
        'P35 online getOne of a record deleted on the server throws 404 and removes the cached copy',
        () async {
      final c = await clients.create();
      final id =
          (await Lab.create('posts', {'title': uniq('P35')}))['id'] as String;
      await c.collection('posts').getOne(id);
      await Lab.delete('posts', id);

      final e = await clientError(() => c.collection('posts').getOne(id));
      expect(e.statusCode, 404);

      expect(
        await c
            .collection('posts')
            .getOneOrNull(id, requestPolicy: RequestPolicy.cacheOnly),
        isNull,
      );
      expect(
        await c
            .collection('posts')
            .watchRecord(id)
            .first
            .timeout(const Duration(seconds: 10)),
        isNull,
      );
      expect(c.connectivity.isConnected, isTrue);
    });

    test(
        'P37 getFullList answered 403 throws ClientException 403 instead of returning cached rows',
        () async {
      final c = await clients.create();
      await c.collection('locked').create(
          body: {'title': uniq('P37 local')},
          requestPolicy: RequestPolicy.cacheOnly);

      final e = await clientError(() => c.collection('locked').getFullList());
      expect(e.statusCode, 403);
      expect(c.connectivity.isConnected, isTrue);
    });
  });
}
