import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:pocketbase/pocketbase.dart';

/// The request never got a usable answer from the server: no connection,
/// a timeout, or a gateway/proxy error while the server is down.
bool isConnectivityFailure(Object error) {
  if (error is ClientException) {
    final s = error.statusCode;
    return s == 0 || s == 502 || s == 503 || s == 504;
  }
  return error is TimeoutException || error is http.ClientException;
}

/// A later retry may succeed: connectivity failures plus request timeouts,
/// rate limits and server errors. Every other 4xx is the server's final
/// answer and must reach the caller.
bool isTransientError(Object error) {
  if (isConnectivityFailure(error)) return true;
  if (error is ClientException) {
    final s = error.statusCode;
    return s == 408 || s == 429 || s >= 500;
  }
  return false;
}

/// Converts transport-level errors to a [ClientException] with status 0, so
/// callers can handle "server not reachable" in one place.
ClientException toNetworkError(Object error, {Uri? url}) {
  if (error is ClientException) return error;
  return ClientException(
    url: url,
    statusCode: 0,
    originalError: error,
    response: {'message': 'The server could not be reached ($error).'},
  );
}

/// PocketBase's answer to a create whose id already exists — the record was
/// created by an earlier attempt whose response was lost.
bool isIdConflict(Object error) {
  if (error is! ClientException || error.statusCode != 400) return false;
  final data = error.response['data'];
  if (data is! Map) return false;
  final id = data['id'];
  return id is Map && id['code'] == 'validation_not_unique';
}

/// The stem PocketBase keeps from an uploaded file name: it stores uploads
/// as `snake_case(name)_<random>.<ext>`.
String pbFileStem(String originalName) {
  final dot = originalName.lastIndexOf('.');
  final base = dot == -1 ? originalName : originalName.substring(0, dot);
  return base
      .replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m[1]}_${m[2]}')
      .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '')
      .toLowerCase();
}

/// The plain field name of a multipart/body key with a PocketBase modifier
/// (`images+`, `+images`, `images-`).
String baseFieldName(String key) =>
    key.replaceAll(RegExp(r'^\+'), '').replaceAll(RegExp(r'[+-]$'), '');

// -- Per-record work -------------------------------------------------------

/// Running pushes and online writes per client, keyed by `collection/id`.
final _recordWork = Expando<Map<String, Future<void>>>();

/// Runs [work] after the running work of every key in [keys] and blocks
/// those records until it is done, so pushes and online writes of a record
/// reach the server one at a time, in order.
Future<T> runForRecords<T>(
  Object client,
  Iterable<String> keys,
  Future<T> Function() work,
) {
  final running = _recordWork[client] ??= {};
  final unique = keys.toSet();
  final previous = [
    for (final key in unique)
      if (running[key] case final future?) future,
  ];
  final result = Future.wait(previous).then((_) => work());
  final done = result.then<void>((_) {}, onError: (Object _) {});
  for (final key in unique) {
    running[key] = done;
  }
  done.whenComplete(() {
    for (final key in unique) {
      if (identical(running[key], done)) running.remove(key);
    }
  });
  return result;
}

/// Whether work of [key] is running or waiting (see [runForRecords]).
bool isRecordBusy(Object client, String key) =>
    _recordWork[client]?.containsKey(key) ?? false;

/// Waits (at most [timeout]) for the work of every key in [keys]. Returns
/// false when some work is still running.
Future<bool> recordsSettle(
  Object client,
  Iterable<String> keys,
  Duration? timeout,
) async {
  final running = _recordWork[client];
  if (running == null) return true;
  final pending = [
    for (final key in keys.toSet())
      if (running[key] case final future?) future,
  ];
  if (pending.isEmpty) return true;
  final all = Future.wait(pending);
  if (timeout == null) {
    await all;
    return true;
  }
  try {
    await all.timeout(timeout);
    return true;
  } on TimeoutException {
    return false;
  }
}

/// Thrown (as the `originalError` of a status-0 [ClientException]) when an
/// online write cannot start because a sync of the record is still running.
class RecordBusy implements Exception {
  const RecordBusy(this.key);
  final String key;

  @override
  String toString() => 'RecordBusy: a sync of $key is still running.';
}

/// Runs the online write [work] of the records [keys] once their running
/// pushes are done (waiting at most [timeout]) and blocks pushes of those
/// records until [work] is done. Throws a status-0 [ClientException] (see
/// [RecordBusy]) when a push does not finish in time: offline-first callers
/// then queue the write behind it.
Future<T> runOnline<T>(
  Object client,
  List<String> keys,
  Duration? timeout,
  Future<T> Function() work,
) async {
  if (!await recordsSettle(client, keys, timeout)) {
    final busy = keys.firstWhere((k) => isRecordBusy(client, k),
        orElse: () => keys.first);
    throw ClientException(
      statusCode: 0,
      originalError: RecordBusy(busy),
      response: {'message': 'A sync of $busy is still running.'},
    );
  }
  return runForRecords(client, keys, work);
}

/// Whether [error] is the [RecordBusy] answer of [runOnline].
bool isRecordBusyError(Object error) =>
    error is ClientException && error.originalError is RecordBusy;
