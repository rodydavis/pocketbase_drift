import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase_drift/pocketbase_drift.dart';

import 'support.dart';

/// Batch requests.
void batchTests() {
  group('batch', () {
    test('P25 batch creates get client-side ids that the server keeps',
        () async {
      final c = await clients.create();
      final prefix = uniq('P25');
      final batch = c.$createBatch();
      batch.collection('tasks').create(body: {'title': '$prefix A'});
      batch.collection('tasks').create(body: {'title': '$prefix B'});

      final results = await batch.send();

      expect(results.every((r) => r.isSuccess), isTrue, reason: '$results');
      final ids = [for (final r in results) r.recordId];
      expect(ids,
          everyElement(isA<String>().having((id) => id.length, 'length', 15)));
      expect([for (final r in results) r.record?.id], ids);
      final onServer = await serverRecords('tasks', 'title ~ "$prefix"');
      expect(onServer.map((r) => r.id), unorderedEquals(ids));
    });

    test('P25b cacheFirst batch never duplicates records on the server',
        () async {
      final c = await clients.create();
      final prefix = uniq('P25b');
      final batch = c.$createBatch();
      batch.collection('tasks').create(body: {'title': '$prefix A'});
      batch.collection('tasks').create(body: {'title': '$prefix B'});

      final results = await batch.send(requestPolicy: RequestPolicy.cacheFirst);
      final ids = [for (final r in results) r.recordId!];
      expect(ids, hasLength(2));
      // Race the background batch send with a sync pass of the same creates.
      await c.syncPendingChanges();

      await eventually(() async => (await pendingIds(c, 'tasks')).isEmpty,
          reason: 'both creates synced');
      await c.syncPendingChanges();
      await Future<void>.delayed(const Duration(milliseconds: 500));

      final onServer = await serverRecords('tasks', 'title ~ "$prefix"');
      expect(onServer.map((r) => r.id), unorderedEquals(ids));
      final local = await c.collection('tasks').getFullList(
          filter: 'title ~ "$prefix"', requestPolicy: RequestPolicy.cacheOnly);
      expect(local.map((r) => r.id), unorderedEquals(ids));
    });
  });
}
