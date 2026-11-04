import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase_drift/pocketbase_drift.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('AuthStore', () {
    late $PocketBase client;
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();

      // Mock connectivity
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel('dev.fluttercommunity.plus/connectivity'),
              (MethodCall methodCall) async => ['wifi']);
    });

    tearDown(() async {
      client.close();
      await client.db.close();
    });

    test('clear() clears database when clearOnLogout is true (default)',
        () async {
      final authStore = $AuthStore.prefs(prefs, 'pb_auth');

      client = $PocketBase.database(
        'http://example.com',
        connection: DatabaseConnection(NativeDatabase.memory()),
        authStore: authStore,
      );

      // Add some data (bypass validation for simple test)
      await client.db
          .$create('users', {'id': 'user1', 'name': 'User 1'}, validate: false);

      // Verify data exists
      var users = await client
          .collection('users')
          .getFullList(requestPolicy: RequestPolicy.cacheOnly);
      expect(users.length, 1);

      // Clear auth (logout)
      client.authStore.clear();

      // Verify data is gone
      users = await client
          .collection('users')
          .getFullList(requestPolicy: RequestPolicy.cacheOnly);
      expect(users.length, 0);
    });

    test(
        'logout keeps pending changes, hidden until the same account logs '
        'in again', () async {
      final authStore = $AuthStore.prefs(prefs, 'pb_auth');
      client = $PocketBase.database(
        'http://example.com',
        connection: DatabaseConnection(NativeDatabase.memory()),
        authStore: authStore,
      );
      await client.db.setSchema([
        {
          'id': 'pbc_notes',
          'name': 'notes',
          'type': 'base',
          'fields': [
            {'id': 'f_text', 'name': 'text', 'type': 'text', 'system': false},
          ],
        },
      ]);
      final account = RecordModel({'id': 'account1'});
      authStore.save('token1', account);

      await client.db.writeLocalCreate(
        'notes',
        {'id': 'pending1', 'text': 'written offline'},
        sync: true,
        owner: 'account1',
      );
      await client.db
          .$create('notes', {'id': 'synced1', 'synced': true}, validate: false);

      client.authStore.clear();

      expect(await client.db.rowById('notes', 'synced1'), isNull,
          reason: 'The cache is wiped on logout');
      expect(await client.db.rowById('notes', 'pending1'), isNotNull,
          reason: 'Unsynced work must survive the logout');
      final visible = await client
          .collection('notes')
          .getFullList(requestPolicy: RequestPolicy.cacheOnly);
      expect(visible, isEmpty,
          reason: "Another account must not see the previous user's changes");
      expect(await client.db.pendingRecords().get(), isEmpty);

      authStore.save('token2', account);
      final again = await client
          .collection('notes')
          .getFullList(requestPolicy: RequestPolicy.cacheOnly);
      expect(again.map((r) => r.id), ['pending1']);
    });

    test('clear() preserves database when clearOnLogout is false', () async {
      final authStore = $AuthStore.prefs(
        prefs,
        'pb_auth',
        clearOnLogout: false,
      );

      client = $PocketBase.database(
        'http://example.com',
        connection: DatabaseConnection(NativeDatabase.memory()),
        authStore: authStore,
      );

      // Add some data (bypass validation for simple test)
      await client.db
          .$create('users', {'id': 'user1', 'name': 'User 1'}, validate: false);

      // Verify data exists
      var users = await client
          .collection('users')
          .getFullList(requestPolicy: RequestPolicy.cacheOnly);
      expect(users.length, 1);

      // Clear auth (logout)
      client.authStore.clear();

      // Verify data is STILL there
      users = await client
          .collection('users')
          .getFullList(requestPolicy: RequestPolicy.cacheOnly);
      expect(users.length, 1);
    });
  });
}
