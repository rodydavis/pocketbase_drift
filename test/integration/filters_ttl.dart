import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase_drift/pocketbase_drift.dart';

import 'support.dart';

/// Local queries matching the server, projections and cache expiry.
void filterTtlTests() {
  group('filters and TTL', () {
    test(
        'P12 TTL maintenance expires rows by cachedAt, including list-fetched rows',
        () async {
      final c = await clients.create();
      final posts = c.collection('posts');
      final prefix = uniq('P12');
      for (var i = 0; i < 3; i++) {
        await Lab.create('posts', {'title': '$prefix #$i'});
      }
      final filter = 'title ~ "$prefix"';
      expect(await posts.getFullList(filter: filter), hasLength(3));
      expect((await posts.getList(filter: filter)).items, hasLength(3));
      // Stays offline, so the queued create remains pending.
      c.connectivity.setConnectivityStatus(false);
      final pending = await posts.create(body: {'title': '$prefix pending'});

      final fresh = await c.runMaintenance(ttl: const Duration(hours: 1));
      expect(fresh.deletedRecords, 0, reason: 'cached just now');

      await Future<void>.delayed(const Duration(milliseconds: 1100));
      final expired = await c.runMaintenance(ttl: Duration.zero);
      expect(expired.deletedRecords, greaterThanOrEqualTo(3));

      final left = await posts.getFullList(
          filter: filter, requestPolicy: RequestPolicy.cacheOnly);
      expect(left.map((r) => r.id), [pending.id],
          reason: 'pending changes are kept');
    });

    test('P13 date macros match the same records locally and on the server',
        () async {
      final c = await clients.create();
      final posts = c.collection('posts');
      final title = uniq('P13');
      await Lab.create('posts', {'title': title});
      expect(await posts.getFullList(filter: 'title = "$title"'), hasLength(1));

      const macros = {
        'created >= @todayStart': 1,
        'created <= @todayEnd': 1,
        'created <= @now': 1,
        'created > @yesterday': 1,
        'created < @tomorrow': 1,
        'created >= @monthStart': 1,
        'created >= @yearStart': 1,
        'created < @todayStart': 0,
        'created > @now': 0,
      };
      for (final macro in macros.entries) {
        final filter = 'title = "$title" && ${macro.key}';
        final server = await posts.getList(
            filter: filter, requestPolicy: RequestPolicy.networkOnly);
        final local = await posts.getFullList(
            filter: filter, requestPolicy: RequestPolicy.cacheOnly);
        expect(server.totalItems, macro.value, reason: 'server: ${macro.key}');
        expect(local, hasLength(macro.value), reason: 'local: ${macro.key}');
      }
    });

    test('P14/P14b filter values with \' " \\ match locally like on the server',
        () async {
      final c = await clients.create();
      final posts = c.collection('posts');
      final suffix = uniq('P14');
      final ids = <String, String>{};
      for (final value in [
        "O'Brien",
        'say "hi"',
        r'back\slash',
        r'''it's "all" \ mixed'''
      ]) {
        final title = '$value $suffix';
        ids[title] =
            (await Lab.create('posts', {'title': title}))['id'] as String;
        await posts.getOne(ids[title]!);
      }

      for (final entry in ids.entries) {
        final filter = c.filter('title = {:t}', {'t': entry.key});
        final server = await posts.getList(
            filter: filter, requestPolicy: RequestPolicy.networkOnly);
        final local = await posts.getFullList(
            filter: filter, requestPolicy: RequestPolicy.cacheOnly);
        expect(server.items.map((r) => r.id), [entry.value],
            reason: 'server: $filter');
        expect(local.map((r) => r.id), [entry.value], reason: 'local: $filter');
      }
    });

    test(
        'P15 fields projections never insert or replace incomplete cached rows',
        () async {
      final c = await clients.create();
      final posts = c.collection('posts');
      final title = uniq('P15');
      final id = (await Lab.create(
              'posts', {'title': title, 'body': 'full body', 'likes': 5}))['id']
          as String;
      final byId = 'id = "$id"';

      Future<void> projectedReads() async {
        await posts.getList(filter: byId, fields: 'id,title');
        await posts.getFullList(filter: byId, fields: 'id,title');
        await posts.getFirstListItem(byId, fields: 'id,title');
        await posts.getOne(id, fields: 'id,title');
      }

      await projectedReads();
      expect(
        await posts.getOneOrNull(id, requestPolicy: RequestPolicy.cacheOnly),
        isNull,
        reason: 'a projection must not insert a row',
      );

      await posts.getOne(id);
      await projectedReads();
      final cached =
          await posts.getOne(id, requestPolicy: RequestPolicy.cacheOnly);
      expect(cached.get<String>('title'), title);
      expect(cached.get<String>('body'), 'full body');
      expect(cached.get<int>('likes'), 5);
      expect(cached.get<String>('collectionName'), 'posts');
    });

    test('P16 offline getList totalItems respects the filter', () async {
      final c = await clients.create();
      final posts = c.collection('posts');
      final prefix = uniq('P16');
      for (final likes in [1, 1, 2]) {
        await Lab.create(
            'posts', {'title': '$prefix likes $likes', 'likes': likes});
      }
      await posts.getFullList(filter: 'title ~ "$prefix"');
      final filter = 'title ~ "$prefix" && likes = 1';

      final server = await posts.getList(
          filter: filter, perPage: 1, requestPolicy: RequestPolicy.networkOnly);
      c.connectivity.setConnectivityStatus(false);
      final local = await posts.getList(filter: filter, perPage: 1);

      expect(server.totalItems, 2);
      expect(local.items, hasLength(1));
      expect(local.totalItems, server.totalItems);
      expect(local.totalPages, server.totalPages);
    });
  });
}
