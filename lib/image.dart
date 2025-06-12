import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pocketbase_drift/pocketbase_drift.dart';

import 'dart:ui' as ui;

class PocketBaseImageProvider extends ImageProvider<PocketBaseImageProvider> {
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
  final int? pixelWidth, pixelHeight;
  final Size? size;
  final Color? color;
  final double? scale;
  final Duration? expireAfter;
  final bool token;

  @override
  ImageStreamCompleter loadImage(
      PocketBaseImageProvider key, ImageDecoderCallback decode) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, decode),
      scale: 1,
      debugLabel: 'PocketBaseImageProvider(${key.filename})',
    );
  }

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
    final double logicWidth = size?.width ?? configuration.size?.width ?? 100;
    final double logicHeight = size?.height ?? configuration.size?.width ?? 100;
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
      ),
    );
  }

  Future<Uint8List?> download() async {
    // The image provider's entire cache/network logic is now handled by the FileService.
    // We use a network-first policy by default for images to ensure they are up-to-date.
    return client.files.get(record, filename,
        requestPolicy: RequestPolicy.cacheAndNetwork, expireAfter: expireAfter);
  }
}
