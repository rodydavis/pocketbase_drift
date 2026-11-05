import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase_drift/pocketbase_drift.dart';

/// Counts the record queries ($query) per collection.
class _QueryCounter extends QueryInterceptor {
  final Map<String, int> byService = {};

  int of(String service) => byService[service] ?? 0;

  @override
  Future<List<Map<String, Object?>>> runSelect(
      QueryExecutor executor, String statement, List<Object?> args) {
    if (statement.startsWith('SELECT * FROM services WHERE service = ?') &&
        !statement.contains(' id IN (') &&
        args.isNotEmpty) {
      byService.update(args.first as String, (v) => v + 1, ifAbsent: () => 1);
    }
    return executor.runSelect(statement, args);
  }
}

Map<String, dynamic> _collection(
        String name, List<Map<String, dynamic>> fields) =>
    {'id': '${name}_col', 'name': name, 'type': 'base', 'fields': fields};

Map<String, dynamic> _relation(String name, String collection) => {
      'name': name,
      'type': 'relation',
      'collectionId': '${collection}_col',
      'maxSelect': 1,
    };

const _title = {'name': 'title', 'type': 'text'};

/// `a.rel` → `c`, `c.d` → `d`; `b` is unrelated.
List<Map<String, dynamic>> _schema({String relTarget = 'c'}) => [
      _collection('a', [_title, _relation('rel', relTarget)]),
      _collection('b', [_title]),
      _collection('c', [_title, _relation('d', 'd')]),
      _collection('d', [_title]),
    ];

Future<void> _idle() => Future<void>.delayed(const Duration(milliseconds: 100));

/// Record watchers re-run only for writes that can change their result:
/// their own collection, the collections they expand, the schema (expand)
/// and writes of unknown collection (raw SQL, `markTablesUpdated`).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/connectivity'),
          (call) async => ['none']);

  test('watchRecords follows a login switch without a new listen', () async {
    final client = $PocketBase.database('http://127.0.0.1:1',
        connection: DatabaseConnection(NativeDatabase.memory()),
        requestPolicy: RequestPolicy.cacheOnly);
    addTearDown(() async {
      client.close();
      await client.db.close();
    });
    await client.db.setSchema(_schema());
    for (final account in ['u1', 'u2']) {
      client.authStore.save('token', RecordModel({'id': account}));
      await client.db.writeLocalCreate('a', {'id': 'p$account', 'title': 'p'},
          sync: true, owner: account);
    }
    client.authStore.save('token', RecordModel({'id': 'u1'}));

    final seen = <List<String>>[];
    final sub = client
        .collection('a')
        .watchRecords(sort: 'id')
        .listen((records) => seen.add([for (final r in records) r.id]));
    await _idle();
    expect(seen.last, ['pu1']);
    seen.clear();
    client.authStore.save('token', RecordModel({'id': 'u2'}));
    await _idle();
    await sub.cancel();
    // Retry bookkeeping of the failed push may emit again; rows of the old
    // account never come back.
    expect(seen, isNotEmpty);
    expect(seen, everyElement(['pu2']));
  });

  for (final background in [false, true]) {
    group(background ? 'watch scope (background isolate)' : 'watch scope', () {
      late DataBase db;
      late _QueryCounter counter;
      Directory? dir;
      String? owner;

      setUp(() async {
        counter = _QueryCounter();
        QueryExecutor executor;
        if (background) {
          dir = await Directory.systemTemp.createTemp('pbd_watch_scope');
          executor =
              NativeDatabase.createInBackground(File('${dir!.path}/db.sqlite'));
        } else {
          executor = NativeDatabase.memory();
        }
        db = DataBase(executor.interceptWith(counter));
        owner = null;
        db.ownerResolver = () => owner;
        await db.setSchema(_schema());
        await db.upsertServerRecords('d', [
          {'id': 'd1', 'title': 'd1'}
        ]);
        await db.upsertServerRecords('c', [
          {'id': 'c1', 'title': 'c1', 'd': 'd1'}
        ]);
        await db.upsertServerRecords('a', [
          {'id': 'a1', 'title': 'a1', 'rel': 'c1'}
        ]);
      });

      tearDown(() async {
        await db.close();
        await dir?.delete(recursive: true);
        dir = null;
      });

      /// Emissions of [query] caused by [action] (the first emission is
      /// dropped).
      Future<List<List<Map<String, dynamic>>>> emissions(
        Selectable<Map<String, dynamic>> query,
        Future<void> Function() action,
      ) async {
        final seen = <List<Map<String, dynamic>>>[];
        final sub = query.watch().listen(seen.add);
        await _idle();
        seen.clear();
        await action();
        await _idle();
        await sub.cancel();
        return seen;
      }

      Future<void> writeB(int count) async {
        for (var i = 0; i < count; i++) {
          await db.upsertServerRecords('b', [
            {'id': 'b$i', 'title': 'b$i'}
          ]);
        }
      }

      Map<String, dynamic> expanded(Map<String, dynamic> row, String field) =>
          (row['expand'] as Map)[field] as Map<String, dynamic>;

      test('writes to another collection do not re-run a watcher', () async {
        final sub = db.$query('a').watch().listen((_) {});
        await _idle();
        final before = counter.of('a');
        await writeB(20);
        await _idle();
        expect(counter.of('a') - before, 0);
        await sub.cancel();
      });

      test('writes to unrelated collections do not re-run an expand watcher',
          () async {
        final sub = db.$query('a', expand: 'rel.d').watch().listen((_) {});
        await _idle();
        final before = counter.of('a');
        await writeB(20);
        await _idle();
        expect(counter.of('a') - before, 0);
        await sub.cancel();
      });

      test('a write to the watched collection re-runs the watcher', () async {
        final seen = await emissions(db.$query('a'), () async {
          await db.upsertServerRecords('a', [
            {'id': 'a2', 'title': 'a2'}
          ]);
        });
        expect(seen.last.map((r) => r['id']), containsAll(['a1', 'a2']));
      });

      test('an expand watcher sees changes two relations away', () async {
        final seen = await emissions(db.$query('a', expand: 'rel.d'), () async {
          await db.upsertServerRecords('d', [
            {
              'id': 'd1',
              'title': 'd1 v2',
              'updated': '2030-01-01 00:00:00.000Z'
            }
          ]);
        });
        final c = expanded(seen.last.single, 'rel');
        expect(expanded(c, 'd')['title'], 'd1 v2');
      });

      test(
          'an expand watcher next to a plain watcher of the same query '
          'still sees related changes', () async {
        final plain = db.$query('a').watch().listen((_) {});
        await _idle();
        final seen = await emissions(db.$query('a', expand: 'rel'), () async {
          await db.upsertServerRecords('c', [
            {
              'id': 'c1',
              'title': 'c1 v2',
              'updated': '2030-01-01 00:00:00.000Z'
            }
          ]);
        });
        await plain.cancel();
        expect(seen, isNotEmpty);
        expect(expanded(seen.last.single, 'rel')['title'], 'c1 v2');
      });

      test('an expand watcher follows a relation moved by a schema change',
          () async {
        final seen = await emissions(db.$query('a', expand: 'rel'), () async {
          // `a.rel` now points to `d`.
          await db.setSchema(_schema(relTarget: 'd'));
          await db.upsertServerRecords('a', [
            {
              'id': 'a1',
              'title': 'a1',
              'rel': 'd1',
              'updated': '2030-01-01 00:00:00.000Z',
            }
          ]);
          await _idle();
          await db.upsertServerRecords('d', [
            {
              'id': 'd1',
              'title': 'd1 v3',
              'updated': '2031-01-01 00:00:00.000Z'
            }
          ]);
        });
        expect(expanded(seen.last.single, 'rel')['title'], 'd1 v3');
      });

      test('raw SQL plus markTablesUpdated reaches record watchers', () async {
        final seen = await emissions(db.$query('a'), () async {
          await db.customStatement(
              "UPDATE services SET data = json_set(data, '\$.title', 'raw') "
              "WHERE service = 'a' AND id = 'a1'");
          db.markTablesUpdated({db.services});
        });
        expect(seen.last.single['title'], 'raw');
      });

      test('customUpdate(updates: {services}) reaches record watchers',
          () async {
        final seen = await emissions(db.$query('a'), () async {
          await db.customUpdate(
            "UPDATE services SET data = json_set(data, '\$.title', 'raw2') "
            "WHERE service = 'a' AND id = 'a1'",
            updates: {db.services},
          );
        });
        expect(seen.last.single['title'], 'raw2');
      });

      test('markTablesUpdated re-runs plain and expand watchers once',
          () async {
        final plain = db.$query('a').watch().listen((_) {});
        final withExpand =
            db.$query('a', expand: 'rel.d').watch().listen((_) {});
        await _idle();
        final before = counter.of('a');
        db.markTablesUpdated({db.services});
        await _idle();
        expect(counter.of('a') - before, 2);
        await plain.cancel();
        await withExpand.cancel();
      });

      group('after an account switch, an open watcher', () {
        /// `p1` is pending for u1, `p2` for u2; u1 is logged in.
        Future<void> pendingOfBothAccounts() async {
          owner = 'u1';
          await db.writeLocalCreate('a', {'id': 'p1', 'title': 'zebra one'},
              sync: true, owner: 'u1');
          owner = 'u2';
          await db.writeLocalCreate('a', {'id': 'p2', 'title': 'zebra two'},
              sync: true, owner: 'u2');
          owner = 'u1';
        }

        /// Emissions of [query] before and after the switch to u2.
        Future<(List<T>, List<List<T>>)> switchAccount<T>(
            Selectable<T> query) async {
          final seen = <List<T>>[];
          final sub = query.watch().listen(seen.add);
          await _idle();
          final before = seen.last;
          seen.clear();
          // What `$PocketBase` does when the logged-in account changes.
          owner = 'u2';
          db.markTablesUpdated({db.services});
          await _idle();
          await sub.cancel();
          return (before, seen);
        }

        Iterable<String> ids(List<Map<String, dynamic>> rows) =>
            rows.map((r) => r['id'] as String);

        test('of a collection shows the new account\'s pending rows only',
            () async {
          await pendingOfBothAccounts();
          final (before, after) =
              await switchAccount(db.$query('a', sort: 'id'));
          expect(ids(before), ['a1', 'p1']);
          expect(after.map(ids), [
            ['a1', 'p2']
          ]);
        });

        test('with expand shows the new account\'s pending rows only',
            () async {
          await pendingOfBothAccounts();
          final (before, after) =
              await switchAccount(db.$query('a', sort: 'id', expand: 'rel'));
          expect(ids(before), ['a1', 'p1']);
          expect(after.map(ids), [
            ['a1', 'p2']
          ]);
        });

        test('of pendingRecords shows the new account\'s queue', () async {
          await pendingOfBothAccounts();
          final (before, after) = await switchAccount(db.pendingRecords());
          expect(before.map((s) => s.id), ['p1']);
          expect(after.map((rows) => rows.map((s) => s.id).toList()), [
            ['p2']
          ]);
        });

        test('of a search shows the new account\'s pending rows only',
            () async {
          await pendingOfBothAccounts();
          final (before, after) =
              await switchAccount(db.search('zebra', service: 'a'));
          expect(before.map((s) => s.id), ['p1']);
          expect(after.map((rows) => rows.map((s) => s.id).toList()), [
            ['p2']
          ]);
        });
      });

      test('pendingRecords().watch() sees local writes', () async {
        final seen = <List<Service>>[];
        final sub = db.pendingRecords().watch().listen(seen.add);
        await _idle();
        await db.writeLocalUpdate('b', 'bx', {'title': 'x'}, sync: true);
        await _idle();
        expect(seen.last.map((s) => s.id), ['bx']);
        await sub.cancel();
      });

      test('writes to two collections in one transaction reach both watchers',
          () async {
        final seenA = <List<Map<String, dynamic>>>[];
        final seenB = <List<Map<String, dynamic>>>[];
        final subA = db.$query('a').watch().listen(seenA.add);
        final subB = db.$query('b').watch().listen(seenB.add);
        await _idle();
        await db.transaction(() async {
          await db.upsertServerRecords('a', [
            {'id': 'a3', 'title': 'a3'}
          ]);
          await db.upsertServerRecords('b', [
            {'id': 'b3', 'title': 'b3'}
          ]);
        });
        await _idle();
        expect(seenA.last.map((r) => r['id']), contains('a3'));
        expect(seenB.last.map((r) => r['id']), contains('b3'));
        await subA.cancel();
        await subB.cancel();
      });

      test('deletes reach the watcher of their collection', () async {
        final seen = await emissions(db.$query('a'), () async {
          await db.deleteSyncedRows('a', ['a1']);
        });
        expect(seen.last, isEmpty);
      });

      test('search watchers see writes', () async {
        final seen = <List<Service>>[];
        final sub = db.search('zebra').watch().listen(seen.add);
        await _idle();
        await db.upsertServerRecords('b', [
          {'id': 'bz', 'title': 'zebra'}
        ]);
        await _idle();
        expect(seen.last.map((s) => s.id), ['bz']);
        await sub.cancel();
      });

      group('ends when the database closes:', () {
        /// Listens to [query], closes the database and waits for done.
        Future<void> expectEndsOnClose<T>(Selectable<T> query,
            {Future<void> Function()? before}) async {
          final done = Completer<void>();
          final sub = query
              .watch()
              .listen((_) {}, onDone: done.complete, onError: (Object _) {});
          await _idle();
          await before?.call();
          await db.close();
          try {
            await done.future.timeout(const Duration(seconds: 2));
          } finally {
            await sub.cancel();
          }
        }

        test(r'$query', () => expectEndsOnClose(db.$query('a')));

        test(r'$query with expand',
            () => expectEndsOnClose(db.$query('a', expand: 'rel.d')));

        test('pendingRecords', () => expectEndsOnClose(db.pendingRecords()));

        test('search', () => expectEndsOnClose(db.search('zebra')));

        test(r'$query rebuilt after an account switch', () {
          return expectEndsOnClose(db.$query('a'), before: () async {
            owner = 'u2';
            db.markTablesUpdated({db.services});
            await _idle();
          });
        });
      });
    });
  }
}
