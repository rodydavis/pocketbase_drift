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
import '../test_server.dart';

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
  final url = testServerUrl;

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
      authStore:
          $AuthStore.prefs(await SharedPreferences.getInstance(), 'pb_auth'),
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

    group('offline scenarios (network failure simulation)', () {
      late $PocketBase offlineClient;
      late $RecordService offlineUltimateService;

      setUp(() async {
        SharedPreferences.setMockInitialValues({});
        // Create a client with a failing HTTP client to simulate network unreachable
        offlineClient = $PocketBase.database(
          'http://127.0.0.1:8888',
          authStore: $AuthStore.prefs(
              await SharedPreferences.getInstance(), 'pb_auth_offline'),
          connection: DatabaseConnection(NativeDatabase.memory()),
          inMemory: true,
          httpClientFactory: () => _FailingHttpClient(),
        );
        offlineClient.logging = true;

        await offlineClient.db
            .setSchema(collections.map((e) => e.toJson()).toList());
        offlineUltimateService = await offlineClient.$collection('ultimate');
      });

      tearDown(() async {
        await offlineClient.db.deleteAll(offlineUltimateService.service);
      });

      test(
          'cacheAndNetwork with network failure: file field name and blob are saved correctly',
          () async {
        const testFileName = 'offline_test.txt';
        const testFileContent = 'Offline file content!';
        final testFile =
            _createDummyFile('file_single', testFileName, testFileContent);

        // Create while network fails using cacheAndNetwork policy
        final createdItem = await offlineUltimateService.create(
          body: {'plain_text': 'offline_record_with_file'},
          files: [testFile],
          requestPolicy: RequestPolicy.cacheAndNetwork,
        );

        // Verify the file field name is saved correctly (not null or empty)
        expect(createdItem.data['file_single'], isNotNull,
            reason: 'File field should not be null when created offline');
        expect(createdItem.data['file_single'], isNotEmpty,
            reason: 'File field should not be empty when created offline');
        expect(createdItem.data['file_single'], testFileName,
            reason: 'File field should contain the original filename');

        // Verify the record can be retrieved with the correct filename
        final cachedRecord = await offlineUltimateService.getOneOrNull(
            createdItem.id,
            requestPolicy: RequestPolicy.cacheOnly);
        expect(cachedRecord, isNotNull);
        expect(cachedRecord!.data['file_single'], testFileName);

        // Verify the file blob was cached
        final cachedFile = await offlineClient.db
            .getFile(createdItem.id, testFileName)
            .getSingleOrNull();
        expect(cachedFile, isNotNull,
            reason: 'File blob should be cached when created offline');
        expect(utf8.decode(cachedFile!.data), testFileContent);
      });

      test(
          'cacheAndNetwork with network failure: update with file saves field name correctly',
          () async {
        // First create a record
        final initialItem = await offlineUltimateService.create(
          body: {'plain_text': 'initial_for_offline_update'},
          requestPolicy: RequestPolicy.cacheAndNetwork,
        );

        const updatedFileName = 'offline_updated.txt';
        const updatedFileContent = 'Updated offline content!';

        // Update with a file while network fails
        final updatedItem = await offlineUltimateService.update(
          initialItem.id,
          body: {'plain_text': 'updated_offline_record'},
          files: [
            _createDummyFile('file_single', updatedFileName, updatedFileContent)
          ],
          requestPolicy: RequestPolicy.cacheAndNetwork,
        );

        // Verify the file field name is saved correctly
        expect(updatedItem.data['file_single'], isNotNull,
            reason: 'File field should not be null after offline update');
        expect(updatedItem.data['file_single'], updatedFileName,
            reason: 'File field should contain the updated filename');

        // Verify the file blob was cached
        final cachedFile = await offlineClient.db
            .getFile(initialItem.id, updatedFileName)
            .getSingleOrNull();
        expect(cachedFile, isNotNull,
            reason: 'File blob should be cached after offline update');
        expect(utf8.decode(cachedFile!.data), updatedFileContent);
      });

      test(
          'cacheAndNetwork with network failure: multiple files are saved correctly',
          () async {
        const testFile1Name = 'offline_multi_1.txt';
        const testFile2Name = 'offline_multi_2.txt';
        const testFile1Content = 'Offline multi 1';
        const testFile2Content = 'Offline multi 2';

        final createdItem = await offlineUltimateService.create(
          body: {'plain_text': 'offline_record_with_multi_files'},
          files: [
            _createDummyFile('file_multi', testFile1Name, testFile1Content),
            _createDummyFile('file_multi', testFile2Name, testFile2Content),
          ],
          requestPolicy: RequestPolicy.cacheAndNetwork,
        );

        final returnedFilenames = createdItem.data['file_multi'] as List;
        expect(returnedFilenames.length, 2);
        expect(returnedFilenames, containsAll([testFile1Name, testFile2Name]));

        // Verify both file blobs were cached
        final cachedFile1 = await offlineClient.db
            .getFile(createdItem.id, testFile1Name)
            .getSingleOrNull();
        final cachedFile2 = await offlineClient.db
            .getFile(createdItem.id, testFile2Name)
            .getSingleOrNull();
        expect(cachedFile1, isNotNull);
        expect(cachedFile2, isNotNull);
        expect(utf8.decode(cachedFile1!.data), testFile1Content);
        expect(utf8.decode(cachedFile2!.data), testFile2Content);
      });
    });

    group('file retrieval fallback behavior', () {
      test('cacheOnly returns expired cached file instead of throwing',
          () async {
        // Manually cache a file with expired timestamp
        const testFileName = 'expired_file.txt';
        const testContent = 'This is expired content';
        final testBytes = Uint8List.fromList(utf8.encode(testContent));
        const testRecordId = 'test_record_expired';

        await client.db.setFile(
          testRecordId,
          testFileName,
          testBytes,
          expires: DateTime.now()
              .subtract(const Duration(hours: 1)), // Already expired
        );

        // Request with cacheOnly should return expired file, not throw
        final retrievedBytes = await client.files.getFileBytes(
          recordId: testRecordId,
          recordCollectionName: 'test',
          filename: testFileName,
          requestPolicy: RequestPolicy.cacheOnly,
        );

        expect(utf8.decode(retrievedBytes), testContent);
      });

      test('cacheAndNetwork returns expired cache when network fails',
          () async {
        // Create a client with failing network
        final failingClient = $PocketBase.database(
          'http://127.0.0.1:8888',
          inMemory: true,
          httpClientFactory: () => _FailingHttpClient(),
        );

        // Manually cache a file with expired timestamp
        const testFileName = 'expired_network_fallback.txt';
        const testContent = 'Fallback content';
        final testBytes = Uint8List.fromList(utf8.encode(testContent));
        const testRecordId = 'test_record_fallback';

        await failingClient.db.setFile(
          testRecordId,
          testFileName,
          testBytes,
          expires: DateTime.now()
              .subtract(const Duration(hours: 1)), // Already expired
        );

        // Request with cacheAndNetwork should try network, fail, then return expired cache
        final retrievedBytes = await failingClient.files.getFileBytes(
          recordId: testRecordId,
          recordCollectionName: 'test',
          filename: testFileName,
          requestPolicy: RequestPolicy.cacheAndNetwork,
        );

        expect(utf8.decode(retrievedBytes), testContent);
      });

      test('cacheOnly throws when no cached file exists', () async {
        // Request a file that doesn't exist in cache with cacheOnly
        expect(
          () => client.files.getFileBytes(
            recordId: 'nonexistent_record',
            recordCollectionName: 'test',
            filename: 'nonexistent_file.txt',
            requestPolicy: RequestPolicy.cacheOnly,
          ),
          throwsException,
        );
      });
    });
  });
}

/// A mock HTTP client that always throws an exception to simulate network failure.
class _FailingHttpClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    throw io.SocketException('Simulated network failure');
  }
}
