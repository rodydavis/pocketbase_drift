// Helpers for the integration suite: a client for the example backend's
// `/api/lab` control routes, a factory for isolated in-memory clients, and
// polling helpers.
import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:pocketbase_drift/pocketbase_drift.dart';

/// Base URL of the example backend (`PB_URL`, default `http://127.0.0.1:8090`).
final String baseUrl =
    _stripSlash(io.Platform.environment['PB_URL'] ?? 'http://127.0.0.1:8090');

String _stripSlash(String url) =>
    url.endsWith('/') ? url.substring(0, url.length - 1) : url;

/// String constants of `example/backend/config/collections.go`, the single
/// source of the backend's seeded credentials.
final Map<String, String> _backendConfig = () {
  final file = io.File('example/backend/config/collections.go');
  if (!file.existsSync()) return const <String, String>{};
  return {
    for (final m
        in RegExp(r'(\w+)\s*=\s*"([^"]*)"').allMatches(file.readAsStringSync()))
      m[1]!: m[2]!,
  };
}();

String _credential(String envKey, String configKey) {
  final value = io.Platform.environment[envKey] ?? _backendConfig[configKey];
  if (value == null) {
    throw StateError('Set $envKey or run from the package root so '
        'example/backend/config/collections.go ($configKey) can be read.');
  }
  return value;
}

/// The seeded lab account (`LAB_EMAIL` / `LAB_PASSWORD` override).
final String labEmail = _credential('LAB_EMAIL', 'LabUserEmail');
final String labPassword = _credential('LAB_PASSWORD', 'LabUserPassword');

/// A second seeded account with the same password.
final String lab2Email = _credential('LAB2_EMAIL', 'LabUser2Email');

/// The superuser reserved for the package's tests.
final String superuserEmail =
    _credential('PB_SUPERUSER_EMAIL', 'TestSuperuserEmail');
final String superuserPassword =
    _credential('PB_SUPERUSER_PASSWORD', 'TestSuperuserPasswd');

/// Thin client for the example backend's `/api/lab` control routes.
abstract final class Lab {
  static Future<dynamic> _post(String path, Map<String, dynamic> body) async {
    final res = await http.post(Uri.parse('$baseUrl/api/lab$path'),
        headers: {'content-type': 'application/json'}, body: jsonEncode(body));
    if (res.statusCode >= 300) {
      throw StateError('lab $path -> ${res.statusCode}: ${res.body}');
    }
    return res.body.isEmpty ? null : jsonDecode(res.body);
  }

  static Future<dynamic> _get(String path) async {
    final res = await http.get(Uri.parse('$baseUrl/api/lab$path'));
    if (res.statusCode >= 300) {
      throw StateError('lab $path -> ${res.statusCode}: ${res.body}');
    }
    return jsonDecode(res.body);
  }

  /// Fails with a clear message when the example backend is not running.
  static Future<void> ensureReachable() async {
    try {
      final res = await http
          .get(Uri.parse('$baseUrl/api/lab/ping'))
          .timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) return;
      throw StateError('status ${res.statusCode}');
    } catch (e) {
      throw StateError('The example backend is not reachable at $baseUrl '
          '($e). Start it with `cd example/backend && go run . serve '
          '--http=127.0.0.1:8090` or set PB_URL.');
    }
  }

  /// Fault injection for requests whose path starts with [match]:
  /// `none`, `latency`, `fail503`, `hang` or `drop`.
  static Future<void> chaos(String mode,
          {String match = '', int latencyMs = 0}) =>
      _post('/chaos', {'mode': mode, 'match': match, 'latencyMs': latencyMs});

  static Future<void> calm() => chaos('none');

  static Future<void> resetStats() => _post('/stats/reset', {});

  /// Sum of the request counters whose route (`METHOD /path`) starts with
  /// [prefix].
  static Future<int> requests(String prefix) async {
    final stats = (await _get('/stats')) as Map<String, dynamic>;
    var n = 0;
    for (final r in (stats['requests'] as List)) {
      if ((r['route'] as String).startsWith(prefix)) n += r['count'] as int;
    }
    return n;
  }

  /// Server-side update that bypasses API rules ("another device").
  static Future<Map<String, dynamic>> mutate(
          String collection, String id, Map<String, dynamic> data) async =>
      (await _post(
              '/mutate', {'collection': collection, 'id': id, 'data': data}))
          as Map<String, dynamic>;

  /// Server-side create that bypasses API rules.
  static Future<Map<String, dynamic>> create(
          String collection, Map<String, dynamic> data) async =>
      (await _post('/create', {'collection': collection, 'data': data}))
          as Map<String, dynamic>;

  static Future<void> delete(String collection, String id) =>
      _post('/delete', {'collection': collection, 'id': id});

  /// The server's record, or null when it does not exist.
  static Future<Map<String, dynamic>?> record(
      String collection, String id) async {
    final res =
        await http.get(Uri.parse('$baseUrl/api/lab/record/$collection/$id'));
    if (res.statusCode == 404) return null;
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<int> count(String collection) async =>
      ((await _get('/count/$collection')) as Map)['count'] as int;

  /// Connected realtime clients: `[{id, subscriptions: {topic: options}}]`.
  static Future<List<Map<String, dynamic>>> realtimeClients() async =>
      ((await _get('/realtime')) as List).cast<Map<String, dynamic>>();

  /// Forcibly closes every realtime (SSE) connection.
  static Future<void> dropRealtime() => _post('/realtime/drop', {});

  static Future<void> seedBig(int count, String group) =>
      _post('/seed-big', {'count': count, 'group': group});
}

PocketBase? _admin;

/// A plain SDK client authenticated as the test superuser.
Future<PocketBase> admin() async {
  final existing = _admin;
  if (existing != null && existing.authStore.isValid) return existing;
  final pb = PocketBase(baseUrl);
  await pb
      .collection('_superusers')
      .authWithPassword(superuserEmail, superuserPassword);
  return _admin = pb;
}

/// Server records of [collection] matching [filter] (superuser view).
Future<List<RecordModel>> serverRecords(
        String collection, String filter) async =>
    (await admin()).collection(collection).getFullList(filter: filter);

List<Map<String, dynamic>>? _schema;

/// Every collection of the backend, as `setSchema` expects it.
Future<List<Map<String, dynamic>>> serverSchema() async {
  return _schema ??= [
    for (final c in await (await admin()).collections.getFullList()) c.toJson(),
  ];
}

/// [serverSchema] without the collection [name].
Future<List<Map<String, dynamic>>> schemaWithout(String name) async => [
      for (final c in await serverSchema())
        if (c['name'] != name) c
    ];

/// Creates isolated clients (in-memory database each) and closes them after
/// every test.
class Clients {
  final _open = <$PocketBase>[];

  /// A new client with the backend schema, logged in as [email] (the lab
  /// account by default) unless [login] is false.
  Future<$PocketBase> create({
    bool login = true,
    String? email,
    List<Map<String, dynamic>>? schema,
    RequestPolicy policy = RequestPolicy.cacheAndNetwork,
    Duration? requestTimeout = const Duration(seconds: 15),
    int localSyncRetryCount = 5,
  }) async {
    final client = track($PocketBase.database(
      baseUrl,
      connection: DatabaseConnection(NativeDatabase.memory()),
      requestPolicy: policy,
      requestTimeout: requestTimeout,
      localSyncRetryCount: localSyncRetryCount,
      authStore: $AuthStore(save: (_) async {}),
    ));
    await client.setSchema(jsonEncode(schema ?? await serverSchema()));
    if (login) {
      await client
          .collection('users')
          .authWithPassword(email ?? labEmail, labPassword);
    }
    return client;
  }

  /// Registers [client] to be closed in tearDown.
  $PocketBase track($PocketBase client) {
    _open.add(client);
    return client;
  }

  void closeAll() {
    for (final c in _open) {
      c.close();
    }
    _open.clear();
  }
}

final clients = Clients();

/// Shared setUp/tearDown: no background probes (tests drive connectivity),
/// chaos off before and after each test, every client closed.
void registerIntegrationHooks() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // flutter_test answers every HTTP request with 400 unless overrides are off.
  io.HttpOverrides.global = null;

  setUpAll(Lab.ensureReachable);
  setUp(() async {
    ConnectivityService.enableProbes = false;
    await Lab.calm();
  });
  tearDown(() async {
    await Lab.calm();
    clients.closeAll();
  });
}

final _runId = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
var _seq = 0;

/// A value unique to this run and call, e.g. for record titles.
String uniq(String label) => '$label $_runId-${_seq++}';

/// Polls [condition] until it holds; fails the test after [timeout].
Future<void> eventually(
  FutureOr<bool> Function() condition, {
  required String reason,
  Duration timeout = const Duration(seconds: 10),
  Duration interval = const Duration(milliseconds: 100),
}) async {
  final watch = Stopwatch()..start();
  while (!await condition()) {
    if (watch.elapsed > timeout) {
      fail('Timed out after ${timeout.inMilliseconds} ms waiting for: $reason');
    }
    await Future<void>.delayed(interval);
  }
}

/// Runs [call] and returns the [ClientException] it must throw.
Future<ClientException> clientError(Future<Object?> Function() call) async {
  try {
    await call();
  } on ClientException catch (e) {
    return e;
  } catch (e) {
    fail('Expected a ClientException, got ${e.runtimeType}: $e');
  }
  fail('Expected a ClientException, but the call succeeded');
}

/// Runs [body] in a guarded zone and returns the errors that escaped it
/// (uncaught zone errors). Errors thrown by [body] itself are rethrown.
Future<List<Object>> uncaughtErrorsOf(Future<void> Function() body) async {
  final uncaught = <Object>[];
  final done = Completer<void>();
  runZonedGuarded(() async {
    try {
      await body();
      done.complete();
    } catch (e, st) {
      done.completeError(e, st);
    }
  }, (e, _) => uncaught.add(e));
  await done.future;
  return uncaught;
}

/// Captures package log lines so tests can assert internal events.
class LogTap {
  LogTap() {
    hierarchicalLoggingEnabled = true;
    Logger.root.level = Level.ALL;
    _sub = Logger.root.onRecord.listen((r) => lines.add(r.message));
  }

  final lines = <String>[];
  late final StreamSubscription<LogRecord> _sub;

  int count(String needle) => lines.where((l) => l.contains(needle)).length;

  Future<void> close() => _sub.cancel();
}

/// Ids of the client's pending local changes in [collection].
Future<List<String>> pendingIds($PocketBase client, String collection) async =>
    [
      for (final r in await client.db.pendingRecords(service: collection).get())
        r.id
    ];

/// 1x1 transparent PNG.
const tinyPng = <int>[
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
];
