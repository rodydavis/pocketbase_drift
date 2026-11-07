import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:pocketbase_drift/pocketbase_drift.dart';

/// An [ImageProvider] that fetches and caches images from a PocketBase instance.
///
/// Bytes are loaded through [$FileService.getFileBytes], which handles the
/// offline blob cache and [RequestPolicy]. Providers with the same client,
/// record, file, [thumb], [scale] and decode size are equal, so Flutter's
/// [ImageCache] reuses the decoded image across rebuilds.
///
/// To limit memory, request a server-side thumbnail with [thumb] and/or a
/// decode size with [pixelWidth]/[pixelHeight] or [size].
class PocketBaseImageProvider extends ImageProvider<PocketBaseImageProvider> {
  /// Creates an [ImageProvider] for a PocketBase file.
  const PocketBaseImageProvider({
    required this.client,
    required this.recordId,
    required this.recordCollectionName,
    required this.filename,
    this.thumb,
    this.pixelWidth,
    this.pixelHeight,
    this.size,
    this.scale,
    this.expireAfter,
    this.token,
    this.autoGenerateToken = false,
    this.requestPolicy = RequestPolicy.cacheAndNetwork,
    this.timeout = const Duration(seconds: 30),
  });

  final $PocketBase client;
  final String recordId;
  final String recordCollectionName;
  final String filename;

  /// PocketBase thumb spec (e.g. `'100x100'`, `'0x300'`) so the server sends a
  /// resized image. Thumbs are cached separately from the original file.
  final String? thumb;

  /// Width in physical pixels to decode the image to.
  ///
  /// With [pixelWidth] and/or [pixelHeight] set, the image is decoded at the
  /// smallest aspect-preserving size that covers the requested dimensions,
  /// and never upscaled.
  final int? pixelWidth;

  /// Height in physical pixels to decode the image to. See [pixelWidth].
  final int? pixelHeight;

  /// Logical size to decode the image for, used when neither [pixelWidth] nor
  /// [pixelHeight] is set; converted to physical pixels with the device pixel
  /// ratio. Without any of them the image is decoded at full resolution.
  final Size? size;

  /// Image pixels per logical pixel; defaults to the device pixel ratio.
  final double? scale;

  /// How long a downloaded file stays valid in the blob cache.
  final Duration? expireAfter;
  final String? token;
  final bool autoGenerateToken;
  final RequestPolicy requestPolicy;

  /// Maximum time for the download before it counts as a network failure.
  final Duration timeout;

  @override
  Future<PocketBaseImageProvider> obtainKey(ImageConfiguration configuration) {
    final dpr = configuration.devicePixelRatio ?? 1.0;
    var targetWidth = pixelWidth;
    var targetHeight = pixelHeight;
    final size = this.size;
    if (targetWidth == null && targetHeight == null && size != null) {
      targetWidth = _toPixels(size.width, dpr);
      targetHeight = _toPixels(size.height, dpr);
    }

    // The key carries the resolved scale and decode size, so equal inputs on
    // the same device produce equal keys.
    return SynchronousFuture<PocketBaseImageProvider>(
      PocketBaseImageProvider(
        client: client,
        recordId: recordId,
        recordCollectionName: recordCollectionName,
        filename: filename,
        thumb: thumb,
        pixelWidth: targetWidth,
        pixelHeight: targetHeight,
        scale: scale ?? dpr,
        expireAfter: expireAfter,
        token: token,
        autoGenerateToken: autoGenerateToken,
        requestPolicy: requestPolicy,
        timeout: timeout,
      ),
    );
  }

  static int? _toPixels(double logical, double devicePixelRatio) {
    if (!logical.isFinite || logical <= 0) return null;
    return math.max(1, (logical * devicePixelRatio).round());
  }

  @override
  ImageStreamCompleter loadImage(
    PocketBaseImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: key._loadAsync(decode),
      scale: key.scale ?? 1.0,
      debugLabel: key.toString(),
      informationCollector: () => <DiagnosticsNode>[
        DiagnosticsProperty<ImageProvider>('Image provider', this),
        DiagnosticsProperty<PocketBaseImageProvider>('Image key', key),
      ],
    );
  }

  Future<ui.Codec> _loadAsync(ImageDecoderCallback decode) async {
    try {
      final bytes = await download();
      if (bytes.isEmpty) {
        throw StateError(
          '$filename is empty and cannot be loaded as an image.',
        );
      }
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      return await decode(
        buffer,
        getTargetSize:
            pixelWidth == null && pixelHeight == null ? null : _targetSize,
      );
    } catch (_) {
      // Drop the failed entry so the next resolve retries the load.
      scheduleMicrotask(() {
        PaintingBinding.instance.imageCache.evict(this);
      });
      rethrow;
    }
  }

  /// Smallest aspect-preserving size covering [pixelWidth] x [pixelHeight],
  /// never larger than the intrinsic size.
  ui.TargetImageSize _targetSize(int intrinsicWidth, int intrinsicHeight) {
    final widthRatio = pixelWidth != null ? pixelWidth! / intrinsicWidth : 0.0;
    final heightRatio =
        pixelHeight != null ? pixelHeight! / intrinsicHeight : 0.0;
    final ratio = math.max(widthRatio, heightRatio);
    if (ratio >= 1) return const ui.TargetImageSize();
    return ui.TargetImageSize(
      width: math.max(1, (intrinsicWidth * ratio).round()),
      height: math.max(1, (intrinsicHeight * ratio).round()),
    );
  }

  /// Downloads the image file bytes through [$FileService.getFileBytes],
  /// which applies [requestPolicy] and the offline blob cache.
  Future<Uint8List> download() {
    return client.files.getFileBytes(
      recordId: recordId,
      recordCollectionName: recordCollectionName,
      filename: filename,
      thumb: thumb,
      token: token,
      autoGenerateToken: autoGenerateToken,
      requestPolicy: requestPolicy,
      expireAfter: expireAfter,
      timeout: timeout,
    );
  }

  @override
  bool operator ==(Object other) {
    if (other.runtimeType != runtimeType) return false;
    return other is PocketBaseImageProvider &&
        identical(other.client, client) &&
        other.recordId == recordId &&
        other.recordCollectionName == recordCollectionName &&
        other.filename == filename &&
        other.thumb == thumb &&
        other.scale == scale &&
        other.pixelWidth == pixelWidth &&
        other.pixelHeight == pixelHeight &&
        other.size == size;
  }

  @override
  int get hashCode => Object.hash(
        identityHashCode(client),
        recordId,
        recordCollectionName,
        filename,
        thumb,
        scale,
        pixelWidth,
        pixelHeight,
        size,
      );

  @override
  String toString() => '${objectRuntimeType(this, 'PocketBaseImageProvider')}('
      '"$recordCollectionName/$recordId/$filename", thumb: $thumb, '
      'scale: $scale, pixelWidth: $pixelWidth, pixelHeight: $pixelHeight)';
}
