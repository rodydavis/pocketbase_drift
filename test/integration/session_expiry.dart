import 'package:flutter_test/flutter_test.dart';

import '../fake_jwt.dart';
import 'support.dart';

/// An expired session against real API rules (`notes`: owner-scoped). The
/// server answers such requests as a guest; the forged token below is
/// treated the same way (bad signature).
void sessionExpiryTests() {
  group('expired session', () {
    test(
        'an expired session keeps the cached notes and the queued edit; a new login syncs and refreshes',
        () async {
      final c = await clients.create();
      final me = c.authStore.record!;
      final notes = c.collection('notes');
      final a = await notes.create(body: {'owner': me.id, 'text': uniq('a')});
      final b = await notes.create(body: {'owner': me.id, 'text': uniq('b')});

      List<String>? shown;
      final sub = notes
          .watchRecords(filter: 'id = "${a.id}" || id = "${b.id}"', sort: 'id')
          .listen((list) => shown = [for (final r in list) r.id]);
      addTearDown(sub.cancel);
      final both = ([a.id, b.id]..sort());
      await eventually(() => shown?.length == 2, reason: 'initial emission');

      c.authStore.save(
        fakeJwt(
            id: me.id,
            expires: DateTime.now().subtract(const Duration(minutes: 1))),
        me,
      );
      await Lab.resetStats();

      // A realtime reconnect refreshes the watchers (PB_CONNECT).
      await Lab.dropRealtime();
      await eventually(() async => (await Lab.realtimeClients()).isNotEmpty,
          timeout: const Duration(seconds: 20), reason: 'realtime reconnect');
      await Future<void>.delayed(const Duration(seconds: 1));
      expect(shown, both, reason: 'the watcher keeps the cached notes');

      final listed = await notes.getFullList(filter: 'id = "${a.id}"');
      expect(listed.map((r) => r.id), [a.id]);

      final edited = uniq('edited');
      await notes.update(a.id, body: {'text': edited});
      await c.syncPendingChanges();
      expect(await pendingIds(c, 'notes'), [a.id]);
      expect(await Lab.requests('PATCH /api/collections/notes'), 0);
      expect((await Lab.record('notes', a.id))!['text'], isNot(edited));

      await c.collection('users').authWithPassword(labEmail, labPassword);
      await eventually(
          () async => (await Lab.record('notes', a.id))!['text'] == edited,
          reason: 'the queued edit syncs after the login');
      await eventually(() async => (await pendingIds(c, 'notes')).isEmpty,
          reason: 'nothing left in the queue');
      expect(shown, both);
    });
  });
}
