import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pocketbase_drift/pocketbase_drift.dart';

// A minimal, valid 1x1 transparent GIF.
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
  group('PocketBaseImageProvider', () {
    late DataBase db;
    late RecordModel dummyRecord;
    const String dummyFilename = 'test_image.gif';

    // Use setUp to ensure a fresh, consistent database for each test.
    setUp(() {
      db = DataBase(connect('test', inMemory: true));
      dummyRecord = RecordModel({
        'id': 'rec123',
        'collectionId': 'col456',
        'data': {'file': dummyFilename}
      });
    });

    // Close the database after each test to prevent leaks.
    tearDown(() async {
      await db.close();
    });

    testWidgets('fetches from network, displays, and caches the image',
        (WidgetTester tester) async {
      // 1. Setup a mock HTTP client that will successfully return our test image.
      final mockHttpClient = MockClient((request) async {
        // We expect a GET request for our specific file.
        if (request.method == 'GET' &&
            request.url.path.endsWith(dummyFilename)) {
          return http.Response.bytes(kTestImageBytes, 200);
        }
        return http.Response('Not Found', 404);
      });

      // 2. Initialize the client with the mock HTTP client.
      final client = $PocketBase(
        'http://mock.pb', // Dummy URL
        db: db,
        httpClientFactory: () => mockHttpClient,
      );

      // 3. Build the widget with the ImageProvider.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Image(
              image: PocketBaseImageProvider(
                client: client,
                record: dummyRecord,
                filename: dummyFilename,
              ),
            ),
          ),
        ),
      );

      // 4. Let the async operations (network fetch, decoding) complete.
      await tester.pumpAndSettle();

      // 5. Verify the image is rendered.
      expect(find.byType(RawImage), findsOneWidget);

      // 6. Verify the image has been saved to the local database cache.
      // We use `watchSingleOrNull` which will emit `null` initially,
      // and then the `BlobFile` once the async `setFile` operation completes.
      db.getFile(dummyRecord.id, dummyFilename).watchSingleOrNull();
      emitsInOrder([
        null, // The state before the file is cached.
        isA<BlobFile>().having((f) => f.data, 'data',
            Uint8List.fromList(kTestImageBytes)), // The state after caching.
      ]);
    });

    testWidgets('fetches from cache when network is unavailable',
        (WidgetTester tester) async {
      int networkCallCount = 0;
      // 1. Setup a mock HTTP client that will FAIL all requests.
      final mockHttpClient = MockClient((request) async {
        networkCallCount++;
        return http.Response('Network Error', 500);
      });

      // 2. Initialize the client.
      final client = $PocketBase(
        'http://mock.pb',
        db: db,
        httpClientFactory: () => mockHttpClient,
      );

      // 3. Manually insert the image into the database cache BEFORE the test.
      await db.setFile(
          dummyRecord.id, dummyFilename, Uint8List.fromList(kTestImageBytes));

      // 4. Build the widget.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Image(
              image: PocketBaseImageProvider(
                client: client,
                record: dummyRecord,
                filename: dummyFilename,
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // 5. Verify the image is rendered (proving it came from the cache).
      expect(find.byType(RawImage), findsOneWidget);

      // 6. Verify that NO successful network call was made.
      // With a valid cache, the FileService should return the cached data
      // immediately and not attempt a network call.
      expect(networkCallCount, 0,
          reason: "No network call should be made when the cache is valid.");
    });
  });
}
