import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logging/logging.dart';
import 'package:pocketbase_drift/pocketbase_drift.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Custom `send` Method Caching', () {
    const String dummyUrl = 'http://mock.pb';
    const String testPath = '/api/custom/test';

    // Helper to create a fresh client for each test, ensuring isolation
    $PocketBase createClient(http.Client httpClient) {
      final client = $PocketBase.database(
        dummyUrl,
        inMemory: true,
        httpClientFactory: () => httpClient,
      );
      client.logging = true;
      return client;
    }

    setUpAll(() {
      hierarchicalLoggingEnabled = true;
      Logger.root.level = Level.ALL;
      Logger.root.onRecord.listen((record) {
        // ignore: avoid_print
        print('${record.level.name}: ${record.time}: ${record.message}');
      });
    });

    setUp(() async {
      ConnectivityService.enableProbes = false;
    });

    test(
        '`cacheAndNetwork` always attempts network and updates cache on success',
        () async {
      int networkCallCount = 0;
      final mockResponse = {'success': true, 'source': 'network'};

      final mockHttpClient = MockClient((request) async {
        if (request.url.path == testPath) {
          networkCallCount++;
          return http.Response(jsonEncode(mockResponse), 200);
        }
        return http.Response('Not Found', 404);
      });

      final client = createClient(mockHttpClient);

      // First call: Should hit the network
      final networkResult = await client.send<Map<String, dynamic>>(
        testPath,
        requestPolicy: RequestPolicy.cacheAndNetwork,
      );
      expect(networkCallCount, 1, reason: "First call should go to network.");
      expect(networkResult, mockResponse);

      // Verify the response is now in the cache
      final cacheKey = 'GET::$testPath::{}::{}';
      final cachedData = await client.db.getCachedResponse(cacheKey);
      expect(cachedData, isNotNull);
      expect(jsonDecode(cachedData!), mockResponse);

      // Second call: Should ALSO hit the network because the policy is network-first
      final secondNetworkResult = await client.send<Map<String, dynamic>>(
        testPath,
        requestPolicy: RequestPolicy.cacheAndNetwork,
      );
      expect(networkCallCount, 2,
          reason:
              "Second call with cacheAndNetwork should also attempt a network fetch.");
      expect(secondNetworkResult, mockResponse);
    });

    test('`cacheAndNetwork` falls back to cache when network request fails',
        () async {
      final mockCacheResponse = {'success': true, 'source': 'cache'};
      int networkCallCount = 0;
      final mockHttpClient = MockClient((request) async {
        networkCallCount++;
        return http.Response('Internal Server Error', 500);
      });

      final client = createClient(mockHttpClient);
      final cacheKey = 'GET::$testPath::{}::{}';

      // Pre-populate the cache
      await client.db.cacheResponse(cacheKey, jsonEncode(mockCacheResponse));

      final result = await client.send<Map<String, dynamic>>(
        testPath,
        requestPolicy: RequestPolicy.cacheAndNetwork,
      );

      expect(networkCallCount, 1,
          reason: "Network should have been attempted.");
      expect(result, mockCacheResponse,
          reason: "Should have returned the cached data on network failure.");
    });

    test('`cacheOnly` returns data from cache and never hits the network',
        () async {
      final mockCacheResponse = {'success': true, 'source': 'cache'};
      int networkCallCount = 0;
      final mockHttpClient = MockClient((request) async {
        networkCallCount++;
        return http.Response('Should not be called', 500);
      });

      final client = createClient(mockHttpClient);
      final cacheKey = 'GET::$testPath::{}::{}';

      await client.db.cacheResponse(cacheKey, jsonEncode(mockCacheResponse));

      final result = await client.send<Map<String, dynamic>>(
        testPath,
        requestPolicy: RequestPolicy.cacheOnly,
      );

      expect(networkCallCount, 0,
          reason: "Network should never be called with cacheOnly policy.");
      expect(result, mockCacheResponse);
    });

    test(
        '`networkOnly` throws an exception on network failure and ignores cache',
        () async {
      final mockCacheResponse = {'success': true, 'source': 'cache'};
      final mockHttpClient =
          MockClient((_) async => http.Response('Network Error', 503));

      final client = createClient(mockHttpClient);
      final cacheKey = 'GET::$testPath::{}::{}';

      await client.db.cacheResponse(cacheKey, jsonEncode(mockCacheResponse));

      expect(
        () => client.send(
          testPath,
          requestPolicy: RequestPolicy.networkOnly,
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('Non-GET requests (e.g., POST) always bypass the cache', () async {
      int networkCallCount = 0;
      final mockResponse = {'created': true};
      final mockHttpClient = MockClient((request) async {
        if (request.method == 'POST') {
          networkCallCount++;
          return http.Response(jsonEncode(mockResponse), 201);
        }
        return http.Response('Not Found', 404);
      });

      final client = createClient(mockHttpClient);

      // First call
      await client.send(
        testPath,
        method: 'POST',
        requestPolicy: RequestPolicy.cacheAndNetwork,
      );
      expect(networkCallCount, 1);

      // Second call should also hit the network
      await client.send(
        testPath,
        method: 'POST',
        requestPolicy: RequestPolicy.cacheAndNetwork,
      );
      expect(networkCallCount, 2);

      // Verify cache is still empty
      final cacheKey = 'POST::$testPath::{}::{}';
      final cachedData = await client.db.getCachedResponse(cacheKey);
      expect(cachedData, isNull);
    });

    test('Different query parameters result in separate cache entries',
        () async {
      int networkCallCount = 0;
      final mockHttpClient = MockClient((request) async {
        networkCallCount++;
        return http.Response(
            jsonEncode({'query': request.url.queryParameters}), 200);
      });

      final client = createClient(mockHttpClient);

      // Call with first set of params to populate cache.
      await client.send(testPath,
          query: {'id': '1'}, requestPolicy: RequestPolicy.cacheAndNetwork);
      expect(networkCallCount, 1, reason: "First network call for id=1.");

      // Call with a second set of params to populate a different cache entry.
      await client.send(testPath,
          query: {'id': '2'}, requestPolicy: RequestPolicy.cacheAndNetwork);
      expect(networkCallCount, 2, reason: "Second network call for id=2.");

      // Now, call with the first set of params again, but explicitly use `cacheOnly`
      // to PROVE that the data was cached correctly and can be retrieved without the network.
      final result = await client.send<Map<String, dynamic>>(testPath,
          query: {'id': '1'}, requestPolicy: RequestPolicy.cacheOnly);

      // The network count should NOT have increased because the policy was `cacheOnly`.
      expect(networkCallCount, 2,
          reason:
              "This call was `cacheOnly` and should not have hit the network.");

      // The result should be the data from the first call, retrieved from the cache.
      expect(result['query']['id'], '1');
    });
  });
}
