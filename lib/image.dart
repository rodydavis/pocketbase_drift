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
  ImageStreamCompleter load(PocketBaseImageProvider key, decode) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, decode),
      scale: 1,
      debugLabel: 'PocketBaseImageProvider(${key.filename})',
    );
  }

  Future<ui.Codec> _loadAsync(PocketBaseImageProvider key, decode) async {
    final bytes = await databaseOrDownload();
    if (bytes == null || bytes.isEmpty) {
      PaintingBinding.instance.imageCache.evict(key);
      throw StateError('${key.filename} is empty and cannot be loaded as an image.');
    }

    return decode(bytes);
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

  Future<Uri> url() async {
    final token = !this.token ? null : await client.files.getToken();
    return client.files.getUrl(record, filename, token: token);
  }

  Future<Uint8List?> download() async {
    final client = this.client.httpClientFactory();
    final url = await this.url();
    debugPrint('url: $url');
    final response = await client.get(url);
    if (response.statusCode == 200) {
      return response.bodyBytes;
    } else {
      return null;
    }
  }

  Future<BlobFile?> database() async {
    final client = await this.client.db.getFile(record.id, filename).getSingleOrNull();
    if (client != null) {
      return client;
    } else {
      return null;
    }
  }

  Future<Uint8List?> databaseOrDownload() async {
    BlobFile? file = await database();
    final now = DateTime.now();
    bool needsUpdate = file?.data == null;
    if (file != null && file.expiration != null && file.expiration!.isBefore(now)) {
      debugPrint('File ${record.id} ${record.collectionName} $filename expired, downloading again');
      needsUpdate = true;
    }
    if (needsUpdate) {
      try {
        final bytes = await download();
        if (bytes != null) {
          file = await client.db.setFile(
            record.id,
            filename,
            bytes,
            expires: expireAfter != null ? now.add(expireAfter!) : null,
          );
        }
      } catch (e) {
        debugPrint('Error downloading file ${record.id} ${record.collectionName} $filename: $e');
      }
    }
    return file?.data;
  }
}
