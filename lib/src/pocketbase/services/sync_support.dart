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
    final busy = keys.firstWhere(
      (k) => isRecordBusy(client, k),
      orElse: () => keys.first,
    );
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

// -- Field deltas ----------------------------------------------------------

/// How a pending field changed when all its local edits were modifiers
/// (`RecordMeta.pendingDeltas`): number `+`/`-`, or multi-value appends
/// (`field+`), prepends (`+field`) or removals only (`field-`).
abstract final class DeltaKind {
  static const number = 'number';
  static const append = 'append';
  static const prepend = 'prepend';
  static const remove = 'remove';

  /// The kind after edits of kinds [a] and [b]; null when they do not mix
  /// (number and list).
  static String? combine(String a, String b) {
    if (a == b) return a;
    if (a == number || b == number) return null;
    if (a == remove) return b;
    if (b == remove) return a;
    // Appends and prepends mixed: the new values are appended.
    return append;
  }
}

List<Object?> _values(Object? value) =>
    value is List ? value : (value == null || value == '' ? const [] : [value]);

/// Request body entries that change [field] from [base] to [local] with
/// modifiers of [kind]: `field+`/`field-` for numbers, `field+` (or
/// `+field`) for added and `field-` for removed values of multi-value
/// fields. For file fields ([files]) only removals are sent; uploads travel
/// as multipart parts. Returns null when the values do not fit [kind]
/// (send the absolute value instead).
Map<String, dynamic>? deltaBody(
  String field,
  String kind,
  Object? base,
  Object? local, {
  bool files = false,
}) {
  if (kind == DeltaKind.number) {
    if (local is! num || (base != null && base is! num)) return null;
    final delta = local - ((base as num?) ?? 0);
    if (delta == 0) return const {};
    return delta > 0 ? {'$field+': delta} : {'$field-': -delta};
  }
  if (local is! List) return null;
  final before = _values(base);
  final added = [
    for (final v in local)
      if (!before.contains(v)) v,
  ];
  final removed = [
    for (final v in before)
      if (!local.contains(v)) v,
  ];
  return {
    if (added.isNotEmpty && !files)
      kind == DeltaKind.prepend ? '+$field' : '$field+': added,
    if (removed.isNotEmpty) '$field-': removed,
  };
}

/// Applies the local change of a [kind] field — from [expected] to [local] —
/// to the [server] value, so the cache shows other devices' changes plus
/// the local change that is still to be sent.
Object? rebaseDelta(
  String kind,
  Object? expected,
  Object? local,
  Object? server,
) {
  if (kind == DeltaKind.number) {
    if (local is! num ||
        (expected != null && expected is! num) ||
        (server != null && server is! num)) {
      return local;
    }
    return ((server as num?) ?? 0) + (local - ((expected as num?) ?? 0));
  }
  if (local is! List) return local;
  final before = _values(expected);
  final removed = {
    for (final v in before)
      if (!local.contains(v)) v,
  };
  final result = [
    for (final v in _values(server))
      if (!removed.contains(v)) v,
  ];
  final added = [
    for (final v in local)
      if (!before.contains(v) && !result.contains(v)) v,
  ];
  if (kind == DeltaKind.prepend) {
    result.insertAll(0, added);
  } else {
    result.addAll(added);
  }
  return result;
}
