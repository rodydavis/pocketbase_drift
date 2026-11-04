import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../../pocketbase_drift.dart';
import 'sync_support.dart';

/// File service with offline caching of downloaded file bytes.
///
/// One instance exists per [$PocketBase] client, so concurrent requests for
/// the same file share a single download.
class $FileService extends FileService {
  $FileService(this.client) : super(client);

  @override
  final $PocketBase client;

  /// Downloads in progress, keyed by collection, record and blob name.
  final _inFlight = <String, _Download>{};

  /// Gets file data, respecting the specified [RequestPolicy].
  ///
  /// This method centralizes the cache-or-network logic for files.
  /// It follows the principle that stale cached data is better than no data
  /// when the network is unavailable:
  /// - A non-expired cached copy is returned without touching the network.
  /// - [RequestPolicy.cacheOnly] never touches the network and returns even an
  ///   expired cached copy.
  /// - If the download fails (including exceeding [timeout]) and an expired
  ///   cached copy exists, that copy is returned; otherwise the error is
  ///   rethrown.
  ///
  /// [thumb] is a PocketBase thumb spec (e.g. `'100x100'`) so the server
  /// returns a resized image. Thumbs are cached separately from the original
  /// file.
  ///
  /// Concurrent calls for the same record, file and [thumb] share one
  /// download; the download uses the [token] and [timeout] of the call that
  /// started it.
  Future<Uint8List> getFileBytes({
    required String recordId,
    required String recordCollectionName,
    required String filename,
    String? thumb,
    String? token,
    bool autoGenerateToken = false,
    RequestPolicy requestPolicy = RequestPolicy.cacheAndNetwork,
    Duration? expireAfter,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final blobName = _blobName(filename, thumb);

    // Try to get cached file first
    BlobFile? cached;
    if (requestPolicy.isCache) {
      cached = await client.db.getFile(recordId, blobName).getSingleOrNull();
      if (cached != null) {
        final now = DateTime.now().toUtc();
        final cacheIsExpired =
            cached.expiration != null && cached.expiration!.isBefore(now);

        // Return valid (non-expired) cache immediately
        if (!cacheIsExpired) {
          return cached.data;
        }

        // For cacheOnly policy, return even expired cache (stale data > no data)
        if (requestPolicy == RequestPolicy.cacheOnly) {
          client.logger.fine(
              'Returning expired cached file (cacheOnly policy): $blobName');
          return cached.data;
        }

        client.logger.fine('Cached file expired, will try network: $blobName');
      }
    }

    // Every policy except cacheOnly may download (cacheFirst on a cache miss
    // or an expired copy).
    if (requestPolicy != RequestPolicy.cacheOnly) {
      try {
        return await _fetch(
          record: RecordModel({
            'id': recordId,
            'collectionName': recordCollectionName,
          }),
          filename: filename,
          blobName: blobName,
          thumb: thumb,
          token: token,
          autoGenerateToken: autoGenerateToken,
          persist: requestPolicy.isCache,
          expireAfter: expireAfter,
          timeout: timeout,
        );
      } catch (e) {
        client.logger.warning('Failed to download file "$blobName": $e');

        // If network failed but we have expired cache, return stale data
        if (cached != null) {
          client.logger
              .fine('Network failed, returning expired cached file: $blobName');
          return cached.data;
        }

        // Network failed and no cache: "server unreachable" is a status-0
        // ClientException, like record reads.
        if (isTransientError(e)) throw toNetworkError(e);
        rethrow;
      }
    }

    throw CacheMissException(
        'File "$blobName" not found in cache (cacheOnly policy)');
  }

  /// Name under which a file (or one of its thumbs) is stored in the blob
  /// cache. `?` never occurs in PocketBase filenames, so thumbs cannot collide
  /// with original files.
  static String _blobName(String filename, String? thumb) =>
      thumb == null || thumb.isEmpty ? filename : '$filename?thumb=$thumb';

  /// Downloads the file (joining an identical download already in flight) and
  /// stores it in the blob cache when [persist] is set.
  Future<Uint8List> _fetch({
    required RecordModel record,
    required String filename,
    required String blobName,
    required String? thumb,
    required String? token,
    required bool autoGenerateToken,
    required bool persist,
    required Duration? expireAfter,
    required Duration timeout,
  }) {
    final key = '${record.collectionName}/${record.id}/$blobName';

    final existing = _inFlight[key];
    if (existing != null) {
      if (!persist || existing.persists) return existing.bytes;
      return existing.bytes.then((bytes) async {
        await _store(record.id, blobName, bytes, expireAfter);
        return bytes;
      });
    }

    final download = _Download(
      () async {
        String? fileToken = token;
        if (autoGenerateToken && fileToken == null) {
          fileToken = await getToken();
        }
        final bytes = await _downloadFile(
          getURL(record, filename, thumb: thumb, token: fileToken),
          timeout,
        );
        if (persist) await _store(record.id, blobName, bytes, expireAfter);
        return bytes;
      }(),
      persists: persist,
    );
    _inFlight[key] = download;
    download.bytes.whenComplete(() {
      if (identical(_inFlight[key], download)) _inFlight.remove(key);
    }).ignore();
    return download.bytes;
  }

  Future<void> _store(
    String recordId,
    String blobName,
    Uint8List bytes,
    Duration? expireAfter,
  ) {
    return client.db.setFile(
      recordId,
      blobName,
      bytes,
      expires:
          expireAfter != null ? DateTime.now().toUtc().add(expireAfter) : null,
    );
  }

  /// Downloads [url] into memory, failing with a [TimeoutException] when the
  /// whole response has not arrived within [timeout].
  Future<Uint8List> _downloadFile(Uri url, Duration timeout) async {
    final httpClient = client.httpClientFactory();
    try {
      return await _readResponse(httpClient, url).timeout(timeout);
    } finally {
      httpClient.close();
    }
  }

  Future<Uint8List> _readResponse(http.Client httpClient, Uri url) async {
    final response = await httpClient.send(http.Request('GET', url));
    final bytes = await response.stream.toBytes();
    if (response.statusCode != 200) {
      throw ClientException(
        url: url,
        statusCode: response.statusCode,
        response: _errorResponse(bytes, response.statusCode),
      );
    }
    return bytes;
  }

  static Map<String, dynamic> _errorResponse(Uint8List body, int statusCode) {
    try {
      final decoded = jsonDecode(utf8.decode(body));
      if (decoded is Map<String, dynamic>) return decoded;
    } on FormatException {
      // Not a JSON error body; fall through to a generic message.
    }
    return {
      'message': 'Failed to download file. Status code: $statusCode',
    };
  }
}

class _Download {
  _Download(this.bytes, {required this.persists});

  final Future<Uint8List> bytes;

  /// Whether the download stores its result in the blob cache.
  final bool persists;
}
