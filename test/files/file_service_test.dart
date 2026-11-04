import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pocketbase_drift/pocketbase_drift.dart';

const _recordId = 'rec1';
const _collection = 'posts';
const _filename = 'photo.jpg';

/// [MockClient] that reports when it is closed.
class _TrackingClient extends MockClient {
  _TrackingClient(super.fn, this.onClose);

  final void Function() onClose;

  @override
  void close() {
    onClose();
    super.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late $PocketBase client;
  late MockClientHandler respond;
  late int requests;
  late int closes;

  setUpAll(() {
    ConnectivityService.enableProbes = false;
  });

  setUp(() {
    requests = 0;
    closes = 0;
    respond = (_) async => http.Response('Not Found', 404);
    client = $PocketBase(
      'http://mock.pb',
      db: DataBase(DatabaseConnection(NativeDatabase.memory())),
      httpClientFactory: () => _TrackingClient((request) {
        requests++;
        return respond(request);
      }, () => closes++),
    );
  });

  tearDown(() {
    client.close();
  });

  Future<Uint8List> getBytes({
    String? thumb,
    RequestPolicy requestPolicy = RequestPolicy.cacheAndNetwork,
    Duration timeout = const Duration(seconds: 30),
  }) =>
      client.files.getFileBytes(
        recordId: _recordId,
        recordCollectionName: _collection,
        filename: _filename,
        thumb: thumb,
        requestPolicy: requestPolicy,
        timeout: timeout,
      );

  test('concurrent requests for one uncached file share one download',
      () async {
    final bytes = Uint8List.fromList(List.generate(4096, (i) => i % 251));
    respond = (request) async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      return http.Response.bytes(bytes, 200);
    };

    final results = await Future.wait(List.generate(6, (_) => getBytes()));

    expect(requests, 1);
    for (final result in results) {
      expect(result, bytes);
    }
    expect(await client.db.getFile(_recordId, _filename).get(), hasLength(1));

    // Once finished, a new network request downloads again.
    await getBytes(requestPolicy: RequestPolicy.networkOnly);
    expect(requests, 2);
  });

  test('cacheFirst downloads on a cache miss, then serves the cache', () async {
    final bytes = Uint8List.fromList([1, 2, 3]);
    respond = (_) async => http.Response.bytes(bytes, 200);

    expect(await getBytes(requestPolicy: RequestPolicy.cacheFirst), bytes);
    expect(await getBytes(requestPolicy: RequestPolicy.cacheFirst), bytes);
    expect(requests, 1);
  });

  test('thumb and full-size files are cached separately', () async {
    final thumbBytes = Uint8List.fromList([1, 1, 1]);
    final fullBytes = Uint8List.fromList([2, 2, 2, 2]);
    respond = (request) async {
      final thumb = request.url.queryParameters['thumb'];
      return http.Response.bytes(
          thumb == '100x100' ? thumbBytes : fullBytes, 200);
    };

    expect(await getBytes(thumb: '100x100'), thumbBytes);
    expect(await getBytes(), fullBytes);
    expect(requests, 2);

    // Both now come from the cache, each with its own bytes.
    expect(await getBytes(requestPolicy: RequestPolicy.cacheOnly), fullBytes);
    expect(
        await getBytes(
            thumb: '100x100', requestPolicy: RequestPolicy.cacheOnly),
        thumbBytes);
    await expectLater(
        getBytes(thumb: '400x0', requestPolicy: RequestPolicy.cacheOnly),
        throwsA(isA<Exception>()));
    expect(requests, 2);
  });

  test('a stalled download times out, falling back to expired cache', () async {
    final stale = Uint8List.fromList([9, 9]);
    respond = (_) => Completer<http.Response>().future;
    const timeout = Duration(milliseconds: 50);

    await expectLater(
        getBytes(timeout: timeout),
        throwsA(isA<ClientException>()
            .having((e) => e.statusCode, 'statusCode', 0)
            .having((e) => e.originalError, 'originalError',
                isA<TimeoutException>())));

    await client.db.setFile(_recordId, _filename, stale,
        expires: DateTime.now().toUtc().subtract(const Duration(minutes: 1)));
    expect(await getBytes(timeout: timeout), stale);
    expect(closes, requests);
  });

  test('non-200 responses throw ClientException with status and url', () async {
    respond = (_) async => http.Response(
        jsonEncode({'status': 404, 'message': 'Not found.', 'data': {}}), 404);

    await expectLater(
      getBytes(),
      throwsA(isA<ClientException>()
          .having((e) => e.statusCode, 'statusCode', 404)
          .having((e) => e.url?.path, 'url.path',
              '/api/files/$_collection/$_recordId/$_filename')
          .having((e) => e.response['message'], 'message', 'Not found.')),
    );
    expect(closes, requests);
  });

  test('closes the http client after a successful download', () async {
    respond = (_) async => http.Response.bytes([1, 2, 3], 200);

    await getBytes(requestPolicy: RequestPolicy.networkOnly);
    await getBytes(requestPolicy: RequestPolicy.networkOnly);

    expect(requests, 2);
    expect(closes, 2);
  });
}
