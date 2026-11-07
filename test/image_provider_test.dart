import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pocketbase_drift/pocketbase_drift.dart';

// A minimal, valid 1x1 transparent GIF.
const kTestImageBytes = <int>[
  0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0x01, 0x00, 0x01, 0x00, 0x80, 0x00, //
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x21, 0xf9, 0x04, 0x01, 0x00, //
  0x00, 0x00, 0x00, 0x2c, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, //
  0x00, 0x02, 0x02, 0x44, 0x01, 0x00, 0x3b,
];

const _recordId = 'rec123';
const _collection = 'test_collection';
const _filename = 'test_image.gif';

/// Encodes a solid [width] x [height] PNG.
Future<Uint8List> _png(int width, int height) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = const Color(0xFF2196F3),
  );
  final image = await recorder.endRecording().toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

/// Resolves [provider] and completes with the first decoded frame.
Future<ImageInfo> _resolve(
    ImageProvider provider, ImageConfiguration configuration) {
  final completer = Completer<ImageInfo>();
  final stream = provider.resolve(configuration);
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      stream.removeListener(listener);
      completer.complete(info);
    },
    onError: (error, stackTrace) {
      stream.removeListener(listener);
      completer.completeError(error, stackTrace);
    },
  );
  stream.addListener(listener);
  return completer.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PocketBaseImageProvider', () {
    late DataBase db;
    late $PocketBase client;
    late MockClientHandler respond;

    setUpAll(() {
      ConnectivityService.enableProbes = false;
    });

    // The client is created, and its start-up sync finished, outside the
    // widget tests' fake async zone: a database query still running on real
    // time would hold the connection while fake-zone queries wait behind it.
    setUp(() async {
      db = DataBase(DatabaseConnection(NativeDatabase.memory()));
      respond = (_) async => http.Response('Not Found', 404);
      client = $PocketBase(
        'http://mock.pb',
        db: db,
        httpClientFactory: () => MockClient((request) => respond(request)),
      );
      await client.syncCompleted;
      PaintingBinding.instance.imageCache
        ..clear()
        ..clearLiveImages();
    });

    tearDown(() {
      client.close();
    });

    PocketBaseImageProvider providerFor({
      String filename = _filename,
      String? thumb,
      int? pixelWidth,
      int? pixelHeight,
      Size? size,
    }) =>
        PocketBaseImageProvider(
          client: client,
          recordId: _recordId,
          recordCollectionName: _collection,
          filename: filename,
          thumb: thumb,
          pixelWidth: pixelWidth,
          pixelHeight: pixelHeight,
          size: size,
        );

    Widget imageApp(ImageProvider provider) => MaterialApp(
          home: Scaffold(body: Image(image: provider)),
        );

    /// Waits (with real async) until [provider] has loaded for the [Image]
    /// in the tree, then rebuilds so the frame is shown.
    Future<void> loadImage(WidgetTester tester, ImageProvider provider) async {
      await tester.runAsync(
          () => precacheImage(provider, tester.element(find.byType(Image))));
      await tester.pump();
    }

    testWidgets('fetches from network, displays, and caches the image',
        (tester) async {
      respond = (request) async {
        if (request.method == 'GET' && request.url.path.endsWith(_filename)) {
          return http.Response.bytes(kTestImageBytes, 200);
        }
        return http.Response('Not Found', 404);
      };

      await tester.pumpWidget(imageApp(providerFor()));
      await loadImage(tester, providerFor());

      expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
      final cached = await tester
          .runAsync(() => db.getFile(_recordId, _filename).getSingleOrNull());
      expect(cached?.data, kTestImageBytes);
    });

    testWidgets('fetches from cache when network is unavailable',
        (tester) async {
      var networkCallCount = 0;
      respond = (request) async {
        networkCallCount++;
        return http.Response('Network Error', 500);
      };
      await tester.runAsync(() => db.setFile(
          _recordId, _filename, Uint8List.fromList(kTestImageBytes)));

      await tester.pumpWidget(imageApp(providerFor()));
      await loadImage(tester, providerFor());

      expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
      expect(networkCallCount, 0,
          reason: 'No network call should be made when the cache is valid.');
    });

    test('equal inputs produce equal providers and keys', () async {
      final otherDb = DataBase(DatabaseConnection(NativeDatabase.memory()));
      final other = $PocketBase('http://mock.pb', db: otherDb);
      addTearDown(other.close);
      const configuration = ImageConfiguration(devicePixelRatio: 2);

      final a = providerFor(thumb: '100x100', size: const Size(50, 50));
      final b = providerFor(thumb: '100x100', size: const Size(50, 50));
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      final keyA = await a.obtainKey(configuration);
      final keyB = await b.obtainKey(configuration);
      expect(keyA, keyB);
      expect(keyA.hashCode, keyB.hashCode);

      expect(providerFor(thumb: '400x0'), isNot(a));
      expect(
        PocketBaseImageProvider(
          client: other,
          recordId: _recordId,
          recordCollectionName: _collection,
          filename: _filename,
          thumb: '100x100',
          size: const Size(50, 50),
        ),
        isNot(a),
      );
      expect(await providerFor(pixelWidth: 100).obtainKey(configuration),
          isNot(await providerFor(pixelWidth: 200).obtainKey(configuration)));
    });

    testWidgets('equal providers share one ImageCache entry', (tester) async {
      var requests = 0;
      respond = (request) async {
        requests++;
        return http.Response.bytes(kTestImageBytes, 200);
      };
      const configuration = ImageConfiguration(devicePixelRatio: 2);

      await tester.runAsync(() => Future.wait([
            _resolve(providerFor(), configuration),
            _resolve(providerFor(), configuration),
          ]));

      expect(PaintingBinding.instance.imageCache.currentSize, 1);
      expect(requests, 1);
    });

    testWidgets('rebuilding with a new equal provider keeps the shown image',
        (tester) async {
      var requests = 0;
      respond = (request) async {
        requests++;
        return http.Response.bytes(kTestImageBytes, 200);
      };

      await tester.pumpWidget(imageApp(providerFor()));
      await loadImage(tester, providerFor());
      final first = tester.widget<RawImage>(find.byType(RawImage)).image;
      expect(first, isNotNull);

      for (var i = 0; i < 10; i++) {
        await tester.pumpWidget(imageApp(providerFor()));
        final shown = tester.widget<RawImage>(find.byType(RawImage)).image;
        expect(shown, isNotNull, reason: 'image must not reload (flash)');
        expect(shown!.isCloneOf(first!), isTrue);
      }

      expect(requests, 1);
      expect(PaintingBinding.instance.imageCache.currentSize, 1);
    });

    testWidgets('decodes at the requested size', (tester) async {
      const filename = 'photo.png';
      respond = (_) async => http.Response('offline', 503);
      await tester.runAsync(() async {
        await db.setFile(_recordId, filename, await _png(400, 200));
      });
      const configuration = ImageConfiguration(devicePixelRatio: 2);

      Future<(int, int)> decodedSize(PocketBaseImageProvider provider) async {
        final info =
            (await tester.runAsync(() => _resolve(provider, configuration)))!;
        final size = (info.image.width, info.image.height);
        info.dispose();
        return size;
      }

      expect(await decodedSize(providerFor(filename: filename)), (400, 200));
      expect(
          await decodedSize(providerFor(filename: filename, pixelWidth: 100)),
          (100, 50));
      expect(
          await decodedSize(providerFor(filename: filename, pixelHeight: 50)),
          (100, 50));
      // Covers the requested box while preserving the aspect ratio.
      expect(
          await decodedSize(providerFor(
              filename: filename, pixelWidth: 100, pixelHeight: 100)),
          (200, 100));
      // Logical size times the device pixel ratio (2): 80x20 -> 160x40 box.
      expect(
          await decodedSize(
              providerFor(filename: filename, size: const Size(80, 20))),
          (160, 80));
      // Never upscales.
      expect(
          await decodedSize(providerFor(filename: filename, pixelWidth: 1000)),
          (400, 200));
    });

    testWidgets('requests and caches the server thumb', (tester) async {
      final requestedThumbs = <String?>[];
      respond = (request) async {
        requestedThumbs.add(request.url.queryParameters['thumb']);
        return http.Response.bytes(kTestImageBytes, 200);
      };

      await tester.runAsync(() =>
          _resolve(providerFor(thumb: '100x100'), ImageConfiguration.empty));

      expect(requestedThumbs, ['100x100']);
      final thumbBlob = await tester.runAsync(
          () => db.getFile(_recordId, '$_filename?thumb=100x100').get());
      final fullBlob =
          await tester.runAsync(() => db.getFile(_recordId, _filename).get());
      expect(thumbBlob, hasLength(1));
      expect(fullBlob, isEmpty);
    });
  });
}
