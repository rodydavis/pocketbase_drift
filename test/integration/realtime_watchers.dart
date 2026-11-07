import 'package:drift/drift.dart' show TableUpdateQuery;
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase_drift/pocketbase_drift.dart';

import '../fake_jwt.dart';
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
          'P26 a bad filter in watchRecordsState (${policy.name}) arrives in QueryState.error, not as a stream or uncaught error',
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
          await eventually(() => states.any((s) => s.hasError),
              reason: 'QueryState.error');
          await Future<void>.delayed(const Duration(milliseconds: 300));
          await sub.cancel();
        });
        expect(errors, isEmpty);
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

  group('realtime and auth changes', () {
    for (final next in ['a guest', 'another account']) {
      test(
          'after a logout to $next, realtime events of the previous account do not reach the cache',
          () async {
        final c = await clients.create();
        final a = c.authStore.record!.id;
        final notes = c.collection('notes');
        await notes.create(body: {'owner': a, 'text': uniq('seed')});
        var shown = <String>[];
        final sub = notes
            .watchRecords()
            .listen((list) => shown = [for (final r in list) r.id]);
        addTearDown(sub.cancel);
        await eventually(() => shown.isNotEmpty, reason: 'initial emission');
        await _realtimeReady(c, 'notes/*');
        final previous = c.realtime.clientId;

        c.authStore.clear();
        if (next == 'another account') {
          await c.collection('users').authWithPassword(lab2Email, labPassword);
        }
        await eventually(
            () =>
                c.realtime.clientId.isNotEmpty &&
                c.realtime.clientId != previous,
            reason: 'realtime reconnects with the current token');
        await _realtimeReady(c, 'notes/*');

        final leaked = (await Lab.create(
            'notes', {'owner': a, 'text': uniq('previous')}))['id'] as String;
        if (next == 'another account') {
          final b = c.authStore.record!.id;
          final own = (await Lab.create(
              'notes', {'owner': b, 'text': uniq('own')}))['id'] as String;
          await eventually(() => shown.contains(own),
              reason: 'the new account gets its own realtime events');
        } else {
          await Future<void>.delayed(const Duration(seconds: 2));
        }
        expect(await c.db.rowById('notes', leaked), isNull);
        expect(shown, isNot(contains(leaked)));
      });
    }

    test(
        'a re-login after a realtime reconnect with an expired token restores realtime events',
        () async {
      final c = await clients.create();
      final me = c.authStore.record!;
      final notes = c.collection('notes');
      final note =
          await notes.create(body: {'owner': me.id, 'text': uniq('a')});
      String? text;
      final sub = notes.watchRecords(filter: 'id = "${note.id}"').listen(
          (list) =>
              text = list.isEmpty ? null : list.single.getStringValue('text'));
      addTearDown(sub.cancel);
      await eventually(() => text != null, reason: 'initial emission');
      await _realtimeReady(c, 'notes/*');

      c.authStore.save(
        fakeJwt(
            id: me.id,
            expires: DateTime.now().subtract(const Duration(minutes: 1))),
        me,
      );
      final beforeDrop = c.realtime.clientId;
      await Lab.dropRealtime();
      await eventually(
          () =>
              c.realtime.clientId.isNotEmpty &&
              c.realtime.clientId != beforeDrop,
          timeout: const Duration(seconds: 20),
          reason: 'realtime reconnects with the expired token');
      await _realtimeReady(c, 'notes/*');

      final guest = c.realtime.clientId;
      await c.collection('users').authWithPassword(labEmail, labPassword);
      await eventually(
          () => c.realtime.clientId.isNotEmpty && c.realtime.clientId != guest,
          reason: 'realtime reconnects with the new token');
      await _realtimeReady(c, 'notes/*');
      // Let the PB_CONNECT refetch finish, so only realtime can deliver.
      await Future<void>.delayed(const Duration(seconds: 1));

      final live = uniq('live');
      await Lab.mutate('notes', note.id, {'text': live});
      await eventually(() => text == live,
          timeout: const Duration(seconds: 5),
          reason: 'the realtime event of the account arrives');
    });

    test('a token refresh of the same account keeps the realtime connection',
        () async {
      final c = await clients.create();
      final sub = c.collection('notes').watchRecords().listen((_) {});
      addTearDown(sub.cancel);
      await _realtimeReady(c, 'notes/*');
      final before = c.realtime.clientId;

      await c.collection('users').authRefresh();
      await Future<void>.delayed(const Duration(seconds: 1));
      expect(c.realtime.clientId, before);
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
