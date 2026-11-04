import 'package:drift/drift.dart' show TableUpdateQuery;
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase_drift/pocketbase_drift.dart';

import 'support.dart';

/// Live queries and realtime events.
void realtimeWatcherTests() {
  group('realtime and watchers', () {
    test(
        'P18 changes made during a realtime drop reach the cache after the reconnect',
        () async {
      final c = await clients.create();
      final target =
          (await Lab.create('posts', {'title': uniq('P18 before')}))['id']
              as String;
      String? latest;
      final sub = c
          .collection('posts')
          .watchRecords(filter: 'id = "$target"')
          .listen((list) =>
              latest = list.isEmpty ? null : list.single.get<String>('title'));
      addTearDown(sub.cancel);
      await eventually(() => latest != null, reason: 'initial emission');
      await _realtimeReady(c, 'posts/*');

      final live = uniq('P18 live');
      await Lab.mutate('posts', target, {'title': live});
      await eventually(() => latest == live, reason: 'live realtime update');

      await Lab.chaos('fail503', match: '/api/realtime');
      await Lab.dropRealtime();
      final duringGap = uniq('P18 during gap');
      await Lab.mutate('posts', target, {'title': duringGap});
      await Future<void>.delayed(const Duration(seconds: 1));
      await Lab.calm();

      await eventually(() => latest == duringGap,
          timeout: const Duration(seconds: 30),
          reason: 'the change made during the gap after the reconnect');

      final after = uniq('P18 after');
      await Lab.mutate('posts', target, {'title': after});
      await eventually(() => latest == after, reason: 'live updates continue');
    });

    test(
        'P20/P20b N watchers of one collection share one realtime subscription; one server event causes one cache write',
        () async {
      final c = await clients.create();
      final target =
          (await Lab.create('posts', {'title': uniq('P20'), 'likes': 1}))['id']
              as String;
      final states = [
        for (var i = 0; i < 4; i++) <QueryState<List<RecordModel>>>[]
      ];
      for (final s in states) {
        final sub = c
            .collection('posts')
            .watchRecordsState(filter: 'id = "$target"')
            .listen(s.add);
        addTearDown(sub.cancel);
      }
      await eventually(
        () => states.every((s) =>
            s.isNotEmpty &&
            !s.last.isFetchingNetwork &&
            s.last.data.length == 1),
        reason: 'all watchers loaded',
      );

      final topics = await _realtimeReady(c, 'posts/*');
      expect(topics.where((t) => t.startsWith('posts')), ['posts/*']);

      var writes = 0;
      final updates = c.db
          .tableUpdates(TableUpdateQuery.onTable(c.db.services))
          .listen((_) => writes++);
      addTearDown(updates.cancel);
      await Lab.mutate('posts', target, {'likes': 42});
      await eventually(
        () => states.every((s) => s.last.data.single.get<int>('likes') == 42),
        reason: 'every watcher sees the event',
      );
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(writes, 1);
    });

    test('P21 watchRecords(limit: n) fetches only n records from the server',
        () async {
      const rows = 3000;
      final existing = await Lab.count('big');
      if (existing < rows) await Lab.seedBig(rows - existing, uniq('P21'));
      final c = await clients.create();
      await Lab.resetStats();

      final states = <QueryState<List<RecordModel>>>[];
      final sub = c
          .collection('big')
          .watchRecordsState(limit: 3, sort: '-created')
          .listen(states.add);
      addTearDown(sub.cancel);
      await eventually(
        () =>
            states.isNotEmpty &&
            !states.last.isFetchingNetwork &&
            states.last.data.length == 3,
        timeout: const Duration(seconds: 30),
        reason: 'the first page arrived',
      );

      expect(await c.db.$count('big'), 3);
      // A full download of $rows rows would take at least 4 pages; a
      // realtime (re)connect may refresh the window once more.
      expect(await Lab.requests('GET /api/collections/big/records'),
          inInclusiveRange(1, 2));
    });

    test('P22 a networkOnly watcher emits the server\'s data', () async {
      final c = await clients.create();
      final title = uniq('P22');
      final id = (await Lab.create('posts', {'title': title}))['id'] as String;

      final first = await c
          .collection('posts')
          .watchRecords(
              filter: 'id = "$id"', requestPolicy: RequestPolicy.networkOnly)
          .first
          .timeout(const Duration(seconds: 10));

      expect(first.map((r) => r.id), [id]);
      expect(first.single.get<String>('title'), title);
      expect(
        await c
            .collection('posts')
            .getOneOrNull(id, requestPolicy: RequestPolicy.cacheOnly),
        isNull,
        reason: 'networkOnly never uses the cache',
      );
    });

    for (final policy in [
      RequestPolicy.cacheOnly,
      RequestPolicy.cacheAndNetwork
    ]) {
      test(
          'P26 a bad filter in watchRecordsState (${policy.name}) arrives as a stream error, not an uncaught error',
          () async {
        final errors = <Object>[];
        final states = <QueryState<List<RecordModel>>>[];
        final uncaught = await uncaughtErrorsOf(() async {
          final c = await clients.create();
          final sub = c
              .collection('posts')
              .watchRecordsState(
                  filter: 'title ==== nope', requestPolicy: policy)
              .listen(states.add, onError: errors.add);
          await eventually(() => errors.isNotEmpty, reason: 'a stream error');
          await eventually(() => states.any((s) => s.hasError),
              reason: 'QueryState.error');
          await Future<void>.delayed(const Duration(milliseconds: 300));
          await sub.cancel();
        });
        expect(uncaught, isEmpty);
      });
    }

    test(
        'P30 writes to another collection cause no extra emissions on a watcher',
        () async {
      final c = await clients.create();
      final prefix = uniq('P30');
      for (var i = 0; i < 3; i++) {
        await c.collection('posts').create(
            body: {'title': '$prefix #$i'},
            requestPolicy: RequestPolicy.cacheOnly);
      }
      final emissions = <List<RecordModel>>[];
      final sub = c
          .collection('posts')
          .watchRecords(requestPolicy: RequestPolicy.cacheOnly)
          .listen(emissions.add);
      addTearDown(sub.cancel);
      await eventually(() => emissions.isNotEmpty, reason: 'initial emission');
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(emissions.single, hasLength(3));

      for (var i = 0; i < 50; i++) {
        await c.collection('big').create(
            body: {'name': '$prefix big $i', 'n': i},
            requestPolicy: RequestPolicy.cacheOnly);
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));

      expect(emissions, hasLength(1));
    });

    test(
        'P36 a realtime event for a collection missing from the local schema causes no uncaught error',
        () async {
      final schema = await schemaWithout('events');
      final title = uniq('P36');
      final emissions = <List<RecordModel>>[];
      final uncaught = await uncaughtErrorsOf(() async {
        final c = await clients.create(schema: schema);
        final sub = c
            .collection('events')
            .watchRecords(filter: 'title = "$title"')
            .listen(emissions.add, onError: (_) {});
        await eventually(() => emissions.isNotEmpty,
            reason: 'initial emission');
        await _realtimeReady(c, 'events/*');
        await Lab.create('events', {'title': title});
        await eventually(() => emissions.last.length == 1,
            reason: 'the realtime event reaches the watcher');
        await Future<void>.delayed(const Duration(milliseconds: 300));
        await sub.cancel();
      });
      expect(uncaught, isEmpty);
    });

    test(
        'P27/P27b records of a collection missing from the local schema are cached and watchable',
        () async {
      final title = uniq('P27');
      final id = (await Lab.create('events', {'title': title}))['id'] as String;
      final c = await clients.create(schema: await schemaWithout('events'));
      final events = c.collection('events');

      final remote = await events.getFullList(filter: 'title = "$title"');
      expect(remote.map((r) => r.id), [id]);

      final cached = await events.getFullList(
          filter: 'title = "$title"', requestPolicy: RequestPolicy.cacheOnly);
      expect(cached.map((r) => r.id), [id]);

      final watched = await events
          .watchRecords(
              filter: 'title = "$title"',
              requestPolicy: RequestPolicy.cacheOnly)
          .first
          .timeout(const Duration(seconds: 10));
      expect(watched.map((r) => r.id), [id]);
    });
  });
}

/// Waits until the server lists [topic] for the client's realtime connection;
/// returns the connection's topics.
Future<List<String>> _realtimeReady($PocketBase c, String topic) async {
  var topics = <String>[];
  await eventually(() async {
    final id = c.realtime.clientId;
    if (id.isEmpty) return false;
    for (final entry in await Lab.realtimeClients()) {
      if (entry['id'] != id) continue;
      topics = [
        ...((entry['subscriptions'] as Map?) ?? const {}).keys.cast<String>()
      ];
      return topics.contains(topic);
    }
    return false;
  }, reason: 'realtime subscription "$topic" active on the server');
  return topics;
}
