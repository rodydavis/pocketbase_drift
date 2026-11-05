import 'dart:convert';
import 'dart:io' as io;
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:pocketbase_drift/pocketbase_drift.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_data/collections.json.dart';
import '../test_server.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  io.HttpOverrides.global = null;

  final url = testServerUrl;

  late $PocketBase client;
  late $RecordService profileService;

  // Simulate a user profile collection with required fields
  final testCollections = [
    ...offlineCollections,
    {
      "id": "test_user_profiles",
      "name": "user_profiles",
      "type": "base",
      "fields": [
        {
          "autogeneratePattern": "[a-z0-9]{15}",
          "hidden": false,
          "id": "text3208210256",
          "max": 15,
          "min": 15,
          "name": "id",
          "pattern": "^[a-z0-9]+\$",
          "presentable": false,
          "primaryKey": true,
          "required": true,
          "system": true,
          "type": "text"
        },
        {
          "autogeneratePattern": "",
          "hidden": false,
          "id": "text_username",
          "max": 50,
          "min": 3,
          "name": "username",
          "pattern": "",
          "presentable": false,
          "primaryKey": false,
          "required": true,
          "system": false,
          "type": "text"
        },
        {
          "exceptDomains": null,
          "hidden": false,
          "id": "email_field",
          "name": "email",
          "onlyDomains": null,
          "presentable": false,
          "required": true,
          "system": false,
          "type": "email"
        },
        {
          "autogeneratePattern": "",
          "hidden": false,
          "id": "text_bio",
          "max": 500,
          "min": 0,
          "name": "bio",
          "pattern": "",
          "presentable": false,
          "primaryKey": false,
          "required": false,
          "system": false,
          "type": "text"
        },
        {
          "autogeneratePattern": "",
          "hidden": false,
          "id": "text_avatar",
          "max": 255,
          "min": 0,
          "name": "avatar_url",
          "pattern": "",
          "presentable": false,
          "primaryKey": false,
          "required": false,
          "system": false,
          "type": "text"
        },
        {
          "hidden": false,
          "id": "number_age",
          "max": 150,
          "min": 0,
          "name": "age",
          "onlyInt": true,
          "presentable": false,
          "required": false,
          "system": false,
          "type": "number"
        }
      ],
      "indexes": [],
      "system": false
    }
  ];

  final collections = testCollections
      .map((e) => CollectionModel.fromJson(jsonDecode(jsonEncode(e))))
      .toList();

  setUpAll(() async {
    hierarchicalLoggingEnabled = true;
    Logger.root.level = Level.WARNING;
    Logger.root.onRecord
        // ignore: avoid_print
        .listen((record) => print('${record.level.name}: ${record.message}'));

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('dev.fluttercommunity.plus/connectivity'),
            (MethodCall methodCall) async => ['wifi']);

    SharedPreferences.setMockInitialValues({});
    client = $PocketBase.database(
      url,
      authStore:
          $AuthStore.prefs(await SharedPreferences.getInstance(), 'pb_auth'),
      connection: DatabaseConnection(NativeDatabase.memory()),
      inMemory: true,
    );

    await client.db.setSchema(collections.map((e) => e.toJson()).toList());
    profileService = await client.$collection('user_profiles');
  });

  group('Partial Update Scenario', () {
    setUp(() async {
      await client.db.deleteAll('user_profiles');
    });

    test('User updates only their bio (offline)', () async {
      // Create a user profile with all required fields
      final profile = await profileService.create(
        body: {
          'username': 'john_doe',
          'email': 'john@example.com',
          'bio': 'Software developer',
          'age': 30,
        },
        requestPolicy: RequestPolicy.cacheOnly,
      );

      expect(profile.data['username'], 'john_doe');
      expect(profile.data['email'], 'john@example.com');

      // User goes offline and updates only their bio
      final updated = await profileService.update(
        profile.id,
        body: {
          'bio': 'Senior Software Engineer passionate about Flutter',
        },
        requestPolicy: RequestPolicy.cacheOnly,
      );

      // Verify all data is preserved
      expect(updated.data['bio'],
          'Senior Software Engineer passionate about Flutter');
      expect(updated.data['username'], 'john_doe');
      expect(updated.data['email'], 'john@example.com');
      expect(updated.data['age'], 30);
    });

    test('User updates avatar and age while offline', () async {
      final profile = await profileService.create(
        body: {
          'username': 'jane_smith',
          'email': 'jane@example.com',
        },
        requestPolicy: RequestPolicy.cacheOnly,
      );

      // Update multiple optional fields at once
      final updated = await profileService.update(
        profile.id,
        body: {
          'avatar_url': 'https://example.com/avatar.jpg',
          'age': 28,
        },
        requestPolicy: RequestPolicy.cacheFirst,
      );

      expect(updated.data['avatar_url'], 'https://example.com/avatar.jpg');
      expect(updated.data['age'], 28);
      expect(updated.data['username'], 'jane_smith');
      expect(updated.data['email'], 'jane@example.com');
    });

    test('Multiple sequential partial updates', () async {
      // Create initial profile
      var profile = await profileService.create(
        body: {
          'username': 'bob_jones',
          'email': 'bob@example.com',
        },
        requestPolicy: RequestPolicy.cacheOnly,
      );

      // Update 1: Add bio
      profile = await profileService.update(
        profile.id,
        body: {'bio': 'Mobile developer'},
        requestPolicy: RequestPolicy.cacheOnly,
      );
      expect(profile.data['bio'], 'Mobile developer');

      // Update 2: Add age
      profile = await profileService.update(
        profile.id,
        body: {'age': 25},
        requestPolicy: RequestPolicy.cacheOnly,
      );
      expect(profile.data['age'], 25);
      expect(profile.data['bio'], 'Mobile developer');

      // Update 3: Change bio
      profile = await profileService.update(
        profile.id,
        body: {'bio': 'Senior Mobile Developer'},
        requestPolicy: RequestPolicy.cacheOnly,
      );

      // Verify everything accumulated correctly
      expect(profile.data['username'], 'bob_jones');
      expect(profile.data['email'], 'bob@example.com');
      expect(profile.data['bio'], 'Senior Mobile Developer');
      expect(profile.data['age'], 25);
    });
  });
}
