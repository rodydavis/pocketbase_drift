import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pocketbase_drift/pocketbase_drift.dart';

// A minimal, valid 1x1 transparent GIF to use as a test file payload.
const kTestImageBytes = <int>[
  0x47,
  0x49,
  0x46,
  0x38,
  0x39,
  0x61,
  0x01,
  0x00,
  0x01,
  0x00,
  0x80,
  0x00,
  0x00,
  0x00,
  0x00,
  0x00,
  0x00,
  0x00,
  0x00,
  0x21,
  0xf9,
  0x04,
  0x01,
  0x00,
  0x00,
  0x00,
  0x00,
  0x2c,
  0x00,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x01,
  0x00,
  0x00,
  0x02,
  0x02,
  0x44,
  0x01,
  0x00,
  0x3b
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('File Service on Web', () {
    late RecordModel dummyRecord;
    const String dummyFilename = 'test_image.gif';

    setUp(() {
      // Use a consistent dummy record for all tests in this group.
      dummyRecord = RecordModel({
        'id': 'rec_web_123',
        'collectionId': 'col_web_456',
        'collectionName': 'web_collection',
        'data': {'file': dummyFilename}
      });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel('dev.fluttercommunity.plus/connectivity'),
              (MethodCall methodCall) async => ['wifi']);
    });

    test('fetches from network, caches, and returns the file', () async {
      // Arrange:
      // 1. Create a mock HTTP client that will successfully return our test image.
      final mockHttpClient = MockClient((request) async {
        final expectedPath =
            '/api/files/${dummyRecord.collectionName}/${dummyRecord.id}/$dummyFilename';
        if (request.method == 'GET' && request.url.path == expectedPath) {
          return http.Response.bytes(kTestImageBytes, 200);
        }
        return http.Response('Not Found', 404);
      });

      // 2. Initialize the client for the web with the mock HTTP client.
      final client = $PocketBase.database(
        'http://mock.pb', // Dummy URL
        inMemory: true, // Use a clean, in-memory Wasm DB for each test
        httpClientFactory: () => mockHttpClient,
      );

      // Act:
      // Request the file. This should trigger a network fetch as the cache is empty.
      final downloadedBytes = await client.files.getFileBytes(
          recordId: dummyRecord.id,
          recordCollectionName: dummyRecord.collectionName,
          filename: dummyFilename);

      // Assert:
      // 1. The downloaded data should be correct.
      expect(downloadedBytes, Uint8List.fromList(kTestImageBytes));

      // 2. The file should now be in the local database cache.
      final cachedFile = await client.db
          .getFile(dummyRecord.id, dummyFilename)
          .getSingleOrNull();
      expect(cachedFile, isNotNull);
      expect(cachedFile!.data, Uint8List.fromList(kTestImageBytes));
    });

    test('fetches from cache when network is unavailable', () async {
      // Arrange:
      // 1. Create a mock HTTP client that always fails.
      int networkCallCount = 0;
      final mockHttpClient = MockClient((request) async {
        networkCallCount++;
        return http.Response('Network Error', 503);
      });

      // 2. Initialize the client for the web.
      final client = $PocketBase.database(
        'http://mock.pb',
        inMemory: true,
        httpClientFactory: () => mockHttpClient,
      );

      // 3. Manually pre-populate the local database cache with the file.
      await client.db.setFile(
          dummyRecord.id, dummyFilename, Uint8List.fromList(kTestImageBytes));

      // Act:
      // Request the file. Because it exists in the cache, it should be returned
      // directly without a network request. We use cacheAndNetwork policy to simulate
      // a real-world scenario where the app would try but fail to connect.
      final cachedBytes = await client.files.getFileBytes(
          recordId: dummyRecord.id,
          recordCollectionName: dummyRecord.collectionName,
          filename: dummyFilename);

      // Assert:
      // 1. The data returned should be correct (from the cache).
      expect(cachedBytes, Uint8List.fromList(kTestImageBytes));

      // 2. The network should not have been successfully called. The get() method
      // in the file service should find the valid cache entry and return it before
      // attempting a network call.
      // NOTE: With cacheAndNetwork, the network might be *attempted*, but the
      // key is that the method succeeds by using the cache. Here we check it wasn't called.
      // A more complex check might be needed if the implementation changes, but for
      // now, the primary test is that we get the data back successfully.
      expect(networkCallCount, 0,
          reason: "A valid cache hit should prevent a network request.");
    });
  });
}
