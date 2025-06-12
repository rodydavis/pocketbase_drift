import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pocketbase_drift/pocketbase_drift.dart';

import 'dart:ui' as ui;

/// An [ImageProvider] that fetches and caches images from a PocketBase instance.
///
/// This provider integrates with PocketBase to retrieve image files associated
/// with a [RecordModel]. It uses the PocketBase SDK's file service, which typically
/// handles caching and network requests.
class PocketBaseImageProvider extends ImageProvider<PocketBaseImageProvider> {
  /// Creates an [ImageProvider] for a PocketBase file.
  PocketBaseImageProvider({
    required this.client,
    required this.record,
    required this.filename,
    this.pixelWidth,
    this.pixelHeight,
    this.size,
    this.color,
    this.scale,
    this.expireAfter,
    this.token = true,
  });

  final $PocketBase client;
  final RecordModel record;
  final String filename;
  final int? pixelWidth;
  final int? pixelHeight;
  final Size? size;
  final Color? color;
  final double? scale;
  final Duration? expireAfter;
  final bool token;

  @override
  ImageStreamCompleter loadImage(
      PocketBaseImageProvider key, ImageDecoderCallback decode) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(
          key, decode), // Asynchronously loads and decodes the image.
      scale: key.scale ?? 1.0,
      debugLabel: 'PocketBaseImageProvider(${key.filename})',
    );
  }

  /// Asynchronously loads the image bytes using the [download] method and then
  /// decodes them using the provided [decode] callback.
  Future<ui.Codec> _loadAsync(PocketBaseImageProvider key, decode) async {
    final bytes = await download();
    if (bytes == null || bytes.isEmpty) {
      PaintingBinding.instance.imageCache.evict(key);
      throw StateError(
          '${key.filename} is empty and cannot be loaded as an image.');
    }

    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }

  static Color getFilterColor(color) {
    if (kIsWeb && color == Colors.transparent) {
      return const Color(0x01ffffff);
    } else {
      return color ?? Colors.transparent;
    }
  }

  @override
  Future<PocketBaseImageProvider> obtainKey(ImageConfiguration configuration) {
    final Color color = this.color ?? Colors.transparent;
    final double scale = this.scale ?? configuration.devicePixelRatio ?? 1.0;

    final double logicWidth = (size ?? configuration.size)?.width ?? 100;

    final double logicHeight = (size ?? configuration.size)?.height ?? 100;

    // Returns a new PocketBaseImageProvider instance configured with the derived values.
    // This new instance serves as the cache key.
    return SynchronousFuture<PocketBaseImageProvider>(
      PocketBaseImageProvider(
        client: client,
        filename: filename,
        record: record,
        scale: scale,
        color: color,
        pixelWidth: (logicWidth * scale).round(),
        pixelHeight: (logicHeight * scale).round(),
        expireAfter: expireAfter,
        token: token,
        size: size,
      ),
    );
  }

  /// Downloads the image file bytes from the PocketBase server.
  ///
  /// This method uses the `client.files.get` method from the PocketBase SDK,
  /// which is expected to handle caching and network policies.
  Future<Uint8List?> download() async {
    // The image provider's entire cache/network logic is now handled by the FileService.
    // We use a network-first policy by default for images to ensure they are up-to-date.
    return client.files.get(record, filename,
        requestPolicy: RequestPolicy.cacheAndNetwork, expireAfter: expireAfter);
  }
}
