import 'dart:convert';
import 'dart:io' as io;
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:pocketbase_drift/pocketbase_drift.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

import '../test_data/collections.json.dart';

http.MultipartFile _createDummyFile(
    String fieldName, String filename, String content) {
  return http.MultipartFile.fromBytes(
    fieldName,
    Uint8List.fromList(utf8.encode(content)),
    filename: filename,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  io.HttpOverrides.global = null;

  const username = 'test@admin.com';
  const password = 'Password123';
  const url = 'http://127.0.0.1:8090';

  late $PocketBase client;
  late $RecordService ultimateService;
  final collections = [...offlineCollections]
      .map((e) => CollectionModel.fromJson(jsonDecode(jsonEncode(e))))
      .toList();

  setUpAll(() async {
    hierarchicalLoggingEnabled = true;
    Logger.root.level = Level.ALL;
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
      authStore: $AuthStore(await SharedPreferences.getInstance(), 'pb_auth'),
      connection: DatabaseConnection(NativeDatabase.memory()),
      inMemory: true,
    );
    client.logging = true;

    await client.collection('_superusers').authWithPassword(username, password);
    await client.db.setSchema(collections.map((e) => e.toJson()).toList());
    ultimateService = await client.$collection('ultimate');
  });

  group('Records File Handling', () {
    for (final requestPolicy in RequestPolicy.values) {
      group(requestPolicy.name, () {
        tearDown(() async {
          // General cleanup of local and remote state
          try {
            final items = await ultimateService.getFullList(
                requestPolicy: RequestPolicy.networkOnly);
            for (final item in items) {
              await ultimateService.delete(item.id,
                  requestPolicy: RequestPolicy.networkOnly);
            }
          } catch (_) {}
          await client.db.deleteAll(ultimateService.service);
        });

        test('create with single file', () async {
          const testFileName = 'test_file.txt';
          const testFileContent = 'Hello PocketBase Drift!';
          final testFile =
              _createDummyFile('file_single', testFileName, testFileContent);

          final createdItem = await ultimateService.create(
            body: {'plain_text': 'record_with_file_${requestPolicy.name}'},
            files: [testFile],
            requestPolicy: requestPolicy,
          );
          expect(createdItem.data['plain_text'],
              'record_with_file_${requestPolicy.name}');

          String expectedFilename;
          if (requestPolicy.isNetwork) {
            expect(createdItem.data['file_single'], isNotNull);
            expect(createdItem.data['file_single'], isNot(testFileName));
            expect(createdItem.data['file_single'], startsWith('test_file_'));
            expectedFilename = createdItem.data['file_single'];
          } else {
            expect(createdItem.data['file_single'], testFileName);
            expectedFilename = testFileName;
          }

          if (requestPolicy.isCache) {
            final cachedRecord = await ultimateService.getOneOrNull(
                createdItem.id,
                requestPolicy: RequestPolicy.cacheOnly);
            expect(cachedRecord, isNotNull);
            expect(cachedRecord!.data['file_single'], expectedFilename);
            final cachedFile = await client.db
                .getFile(createdItem.id, expectedFilename)
                .getSingleOrNull();
            expect(cachedFile, isNotNull);
            expect(utf8.decode(cachedFile!.data), testFileContent);
          }
        });

        test('create with multiple files', () async {
          const testFileContent1 = 'Hello multi 1!';
          const testFileContent2 = 'Hello multi 2!';
          final testFile1 =
              _createDummyFile('file_multi', 'multi_1.txt', testFileContent1);
          final testFile2 =
              _createDummyFile('file_multi', 'multi_2.txt', testFileContent2);

          final createdItem = await ultimateService.create(
            body: {
              'plain_text': 'record_with_multi_file_${requestPolicy.name}'
            },
            files: [testFile1, testFile2],
            requestPolicy: requestPolicy,
          );

          final returnedFilenames = createdItem.data['file_multi'] as List;
          expect(returnedFilenames.length, 2);

          List<String> expectedFilenames;
          if (requestPolicy.isNetwork) {
            expect(
                returnedFilenames.any((f) => f.startsWith('multi_1_')), isTrue);
            expect(
                returnedFilenames.any((f) => f.startsWith('multi_2_')), isTrue);
            expectedFilenames = returnedFilenames.cast<String>();
          } else {
            expect(
                returnedFilenames, containsAll(['multi_1.txt', 'multi_2.txt']));
            expectedFilenames = ['multi_1.txt', 'multi_2.txt'];
          }

          if (requestPolicy.isCache) {
            final cachedRecord = await ultimateService.getOneOrNull(
                createdItem.id,
                requestPolicy: RequestPolicy.cacheOnly);
            expect(cachedRecord!.data['file_multi'],
                containsAll(expectedFilenames));
          }
        });

        test('update with single file', () async {
          final initialItem = await ultimateService.create(
            body: {'plain_text': 'initial_for_file_update'},
            requestPolicy: RequestPolicy.cacheAndNetwork,
          );
          const updatedFile = "updated_file.txt";
          final updatedItem = await ultimateService.update(
            initialItem.id,
            body: {'plain_text': 'updated_record_with_file'},
            files: [_createDummyFile('file_single', updatedFile, 'updated')],
            requestPolicy: requestPolicy,
          );
          if (requestPolicy.isNetwork) {
            expect(
                updatedItem.data['file_single'], startsWith('updated_file_'));
          } else {
            expect(updatedItem.data['file_single'], updatedFile);
          }
        });
      });
    }

    test('deleting a record also deletes its cached file', () async {
      const testFileName = 'cleanup_test.txt';
      const testFileContent = 'This file should be cleaned up.';
      final testFile =
          _createDummyFile('file_single', testFileName, testFileContent);

      final createdItem = await ultimateService.create(
        body: {'plain_text': 'record_for_file_cleanup'},
        files: [testFile],
        requestPolicy: RequestPolicy.cacheAndNetwork,
      );

      final serverFilename = createdItem.data['file_single'] as String;
      expect(serverFilename, isNotNull);

      final cachedFileBefore = await client.db
          .getFile(createdItem.id, serverFilename)
          .getSingleOrNull();
      expect(cachedFileBefore, isNotNull,
          reason: "File should be cached after creation.");
      expect(utf8.decode(cachedFileBefore!.data), testFileContent);

      await ultimateService.delete(createdItem.id,
          requestPolicy: RequestPolicy.cacheAndNetwork);

      final cachedFileAfter = await client.db
          .getFile(createdItem.id, serverFilename)
          .getSingleOrNull();
      expect(cachedFileAfter, isNull,
          reason:
              "File blob should be deleted from cache when the record is deleted.");
    });
  });
}
