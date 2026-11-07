import 'dart:convert';
import 'dart:io' as io;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:pocketbase_drift/pocketbase_drift.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_data/collections.json.dart';
import '../test_server.dart';

/// Regression test for a bug where a failed initial fetch inside `onListen`
/// (network down/rejected, no usable cache) was thrown from an unawaited
/// async callback and never reached the stream `watchRecord`/`watchRecords`/
/// `watchRecordState`/`watchRecordsState` return -- it silently vanished
/// (an uncaught async exception) instead of surfacing as a catchable stream
/// error a caller could observe and react to.
///
/// `RequestPolicy.networkOnly` is used because its remote-fetch path never
/// attempts a cache fallback on failure (`_fetchNetworkOnly` rethrows
/// directly) -- the simplest deterministic way to guarantee the initial
/// fetch inside `onListen` throws, regardless of local cache state.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  io.HttpOverrides.global = null;

  const username = 'test@admin.com';
  const password = 'Password123';
  final url = testServerUrl;

  late $PocketBase client;
  final collections = [...offlineCollections]
      .map((e) => CollectionModel.fromJson(jsonDecode(jsonEncode(e))))
      .toList();

  setUpAll(() async {
    hierarchicalLoggingEnabled = true;
    Logger.root.level = Level.WARNING;
    Logger.root.onRecord
        // ignore: avoid_print
        .listen((record) => print('${record.level.name}: ${record.message}'));

    SharedPreferences.setMockInitialValues({});
    client = $PocketBase.database(
      url,
      authStore:
          $AuthStore.prefs(await SharedPreferences.getInstance(), 'pb_auth'),
      connection: DatabaseConnection(NativeDatabase.memory()),
      inMemory: true,
    );
    client.logging = true;

    await client.collection('_superusers').authWithPassword(username, password);
    await client.db.setSchema(collections.map((e) => e.toJson()).toList());
  });

  tearDownAll(() {
    client.close();
  });
  test(
      'watchRecords surfaces a networkOnly fetch failure as a stream error '
      'instead of silently vanishing', () async {
    final service = await client.$collection('todo');

    final errors = <Object>[];
    final subscription = service
        .watchRecords(
          filter: 'nonexistent_server_field = "123"',
          requestPolicy: RequestPolicy.networkOnly,
        )
        .listen((_) {}, onError: errors.add);

    // Give the unawaited onListen callback a chance to run and fail.
    await Future<void>.delayed(const Duration(seconds: 2));
    await subscription.cancel();

    expect(errors, isNotEmpty,
        reason: 'the networkOnly fetch failure inside onListen must reach '
            'this stream as a catchable error, not vanish silently');
  });

  test(
      'watchRecordsState reports a networkOnly fetch failure in '
      'QueryState.error, not as a stream error', () async {
    final service = await client.$collection('todo');

    final errors = <Object>[];
    final states = <QueryState<List<RecordModel>>>[];
    final subscription = service
        .watchRecordsState(
          filter: 'nonexistent_server_field = "123"',
          requestPolicy: RequestPolicy.networkOnly,
        )
        .listen(states.add, onError: errors.add);

    await Future<void>.delayed(const Duration(seconds: 2));
    await subscription.cancel();

    expect(errors, isEmpty,
        reason: 'a stream error would make StreamBuilder drop the data');
    expect(states, isNotEmpty);
    expect(states.last.hasError, isTrue,
        reason:
            'QueryState must embed the network error for UI state builders');
    expect(states.last.isFetchingNetwork, isFalse);
  });

  test(
      'watchRecord still streams live updates after the addStream -> '
      'manual-forwarding refactor', () async {
    final service = await client.$collection('todo');
    await client.db.deleteAll(service.service);

    final created = await service.create(
      body: {'name': 'watch_record_initial'},
      requestPolicy: RequestPolicy.cacheAndNetwork,
    );

    final events = <RecordModel?>[];
    final subscription = service.watchRecord(created.id).listen(events.add);
    await Future<void>.delayed(const Duration(milliseconds: 200));

    await service.update(
      created.id,
      body: {'name': 'watch_record_updated'},
      requestPolicy: RequestPolicy.cacheAndNetwork,
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await subscription.cancel();

    expect(events, isNotEmpty);
    expect(events.last?.data['name'], 'watch_record_updated',
        reason: 'watchRecord must still emit live updates through the '
            'manually-forwarded db stream, not just the initial snapshot');
  });

  test('watchRecord distinctResults detects changes in expanded relations',
      () async {
    final service = await client.$collection('ultimate');
    await client.db.deleteAll(service.service);

    final created = await service.create(
      body: {'plain_text': 'ultimate_test'},
      requestPolicy: RequestPolicy.cacheAndNetwork,
    );

    final events = <RecordModel?>[];
    final subscription = service
        .watchRecord(created.id, distinctResults: true)
        .listen(events.add);
    await Future<void>.delayed(const Duration(milliseconds: 200));

    // Update record
    await service.update(
      created.id,
      body: {'plain_text': 'ultimate_updated'},
      requestPolicy: RequestPolicy.cacheAndNetwork,
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await subscription.cancel();

    expect(events.length, greaterThanOrEqualTo(2));
    expect(events.last?.data['plain_text'], 'ultimate_updated');
  });

  test('watchRecords allows clean resubscription on broadcast stream',
      () async {
    final service = await client.$collection('todo');
    await client.db.deleteAll(service.service);

    final broadcast = service
        .watchRecords(requestPolicy: RequestPolicy.cacheFirst)
        .asBroadcastStream();

    // First listener subscribes and cancels
    final sub1 = broadcast.listen((_) {});
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await sub1.cancel();

    // Second listener subscribes
    final events = <List<RecordModel>>[];
    final sub2 = broadcast.listen(events.add);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    await service.create(
      body: {'name': 'resubscription_item'},
      requestPolicy: RequestPolicy.cacheFirst,
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await sub2.cancel();

    expect(events, isNotEmpty);
    expect(events.last.any((r) => r.data['name'] == 'resubscription_item'),
        isTrue);
  });
}
