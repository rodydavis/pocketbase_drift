# Setup

This guide covers installing and configuring pocketbase_drift.

## Installation

Add to `pubspec.yaml`:

```yaml
dependencies:
  pocketbase_drift: ^0.7.0  # Use latest version
```

## Initialize the Client

Replace standard PocketBase client with `$PocketBase.database`:

```dart
import 'package:pocketbase_drift/pocketbase_drift.dart';

// Simple initialization
final client = $PocketBase.database('http://127.0.0.1:8090');

// With options
final client = $PocketBase.database(
  'http://127.0.0.1:8090',
  dbName: 'my_app.db',           // Custom database filename
  inMemory: false,                // Use persistent storage
  cacheTtl: Duration(days: 60),   // Cache expiration (by cache time, cachedAt)
  requestTimeout: Duration(seconds: 15), // Single-record reads and writes; null disables
  maxFileCacheBytes: 128 * 1024 * 1024,  // File blob cache limit (LRU); null = no limit
);
```

On Android, iOS and desktop, SQLite runs in a background isolate (WAL mode). Database work does not block the UI isolate. `inMemory: true` keeps the database on the calling isolate.

## Cache the Schema

To enable offline record functionality, cache your schema:

### 1. Export Schema from PocketBase

Go to PocketBase Admin UI → Settings → Export collections → Download `pb_schema.json`

### 2. Add to Assets

```yaml
# pubspec.yaml
flutter:
  assets:
    - assets/pb_schema.json
```

### 3. Cache on Startup

```dart
import 'package:flutter/services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load schema
  final schema = await rootBundle.loadString('assets/pb_schema.json');
  
  // Initialize client and cache schema
  final client = $PocketBase.database('http://127.0.0.1:8090');
  await client.setSchema(schema);
  runApp(MyApp(client: client));
}
```

Await `setSchema`. Record reads and writes wait for a pending `setSchema`, so an un-awaited `..setSchema(schema)` does not race the first write. But `setSchema` throws on invalid schema JSON. Only an awaited call shows that error at startup.

## Authentication Store

Use `$AuthStore` for persistent authentication:

```dart
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  
  // Create persistent auth store
  final authStore = $AuthStore.prefs(prefs, 'pb_auth');
  
  // Initialize client with auth store
  final client = $PocketBase.database(
    'http://127.0.0.1:8090',
    authStore: authStore,
  );
  
  // Load schema
  final schema = await rootBundle.loadString('assets/pb_schema.json');
  await client.setSchema(schema);
  runApp(MyApp(client: client));
}
```

`$AuthStore.prefs(prefs, key, clearOnLogout: true)` is the default. On logout (`authStore.clear()`), the cache is deleted but unsynced changes of the account stay. They sync when the same account logs in again. See `sync.md`.

## Web Setup

For web platform, you need Drift's WASM files. The worker loads the wasm, so both must come from the same release.

### 1. Download Required Files

Take **both** files from the [drift release](https://github.com/simolus3/drift/releases) (tag `drift-<version>`) that matches the `drift` version in `pubspec.lock`:

- `sqlite3.wasm`
- `drift_worker.js`

Never take `sqlite3.wasm` from a newer [sqlite3.dart release](https://github.com/simolus3/sqlite3.dart/releases) than the worker: the sqlite3 3.9.0 wasm with the drift 2.35.3 worker fails with `LinkError ... "dart" "dispatch_trace"` and the database never opens. To use a newer wasm, compile the worker against the app's lock (`tool/drift_worker.dart` with `void main() => WasmDatabase.workerMainForOpen();`, `dart compile js -O4 tool/drift_worker.dart -o web/drift_worker.js`, `drift` in `dev_dependencies`) and take `sqlite3.wasm` from the `sqlite3-<version>` release of the locked `sqlite3`. See README "4. Web Setup".

### 2. Add to Web Directory

```
web/
├── drift_worker.js
├── sqlite3.wasm
└── index.html
```

### 3. Verify

The app will automatically use the web-compatible database on web platform.

## Riverpod Integration

Create the client before `runApp`, await `setSchema`, then override the client provider with it. The example app (`example/lib/shared/providers/pocketbase_provider.dart`) uses this pattern. It names the provider `pocketBaseProvider`.

```dart
// lib/shared/providers/pocketbase_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocketbase_drift/pocketbase_drift.dart';
import 'package:shared_preferences/shared_preferences.dart';

// SharedPreferences provider (override in main)
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('Override in main.dart');
});

/// Creates the client and caches the schema before it returns.
Future<$PocketBase> createPocketBaseClient(
  SharedPreferences prefs,
  String schemaJson,
) async {
  final client = $PocketBase.database(
    const String.fromEnvironment('POCKETBASE_URL',
      defaultValue: 'http://127.0.0.1:8090'),
    authStore: $AuthStore.prefs(prefs, 'pb_auth'),
  );
  await client.setSchema(schemaJson);
  return client;
}

// PocketBase client provider (override in main with the created client)
final pocketbaseProvider = Provider<$PocketBase>((ref) {
  throw UnimplementedError('Override in main.dart');
});
```

### Main.dart with Riverpod

```dart
// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load dependencies in parallel
  final startupValues = await Future.wait([
    SharedPreferences.getInstance(),
    rootBundle.loadString('assets/pb_schema.json'),
  ]);
  
  final sharedPreferences = startupValues[0] as SharedPreferences;
  final schemaJson = startupValues[1] as String;

  // The schema is cached before any record is written or validated.
  final client = await createPocketBaseClient(sharedPreferences, schemaJson);

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(sharedPreferences),
        pocketbaseProvider.overrideWith((ref) {
          ref.onDispose(client.close);
          return client;
        }),
      ],
      child: const MyApp(),
    ),
  );
}
```

## Enable Logging

For debugging, enable the client logger:

```dart
final client = $PocketBase.database('http://127.0.0.1:8090');
client.logging = true; // Enables detailed logging

// Log levels include:
// - INFO: Sync events, connectivity changes
// - FINE: Individual operations
// - WARNING: Recoverable errors
// - SEVERE: Critical errors
```

## Configuration Summary

| Option | Default | Description |
|--------|---------|-------------|
| `baseUrl` | Required | PocketBase server URL |
| `dbName` | `'pb_drift.db'` | SQLite database filename |
| `inMemory` | `false` | Use in-memory database (for tests) |
| `cacheTtl` | `60 days` | Cache expiration for maintenance (by `cachedAt`) |
| `authStore` | Auto-created | Custom auth store for persistence |
| `httpClientFactory` | Default | Custom HTTP client factory |
| `requestPolicy` | `cacheAndNetwork` | Default policy for all service methods |
| `localSyncRetryCount` | `5` | Rejections before a pending change is parked |
| `requestTimeout` | `15 s` | Limit for single-record reads and writes without file uploads. `null` disables it. |
| `maxFileCacheBytes` | `$PocketBase.defaultMaxFileCacheBytes` (128 MB; 32 MB on the web) | Size limit of the file blob cache. Eviction deletes blobs larger than 90% of the limit first, then the least recently used ones; blobs of pending and local-only records are never deleted. Files larger than 90% of the limit are not cached (unsynced uploads are). `null` disables it. See `files.md`. |
| `connection` | Native: background isolate | Custom Drift `DatabaseConnection` |
| `connectivityProbeTimeout` | `5 s` | Timeout of a server health probe |
| `connectivityOnlineProbeInterval` | `60 s` | Probe interval while online |
| `connectivityOfflineBackoffMin` / `Max` | `5 s` / `60 s` | Probe backoff while offline |

## Widget Tests

The client starts a sync pass when it is created. A database query that still runs on real time blocks the queries of the fake-async zone of `testWidgets`. Do these two steps:
1. Create the client outside the fake-async zone (in `setUp`, not inside `testWidgets`).
2. `await client.syncCompleted` in `setUp`.

```dart
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// Inside main() / group():
late $PocketBase client;

setUpAll(() {
  ConnectivityService.enableProbes = false; // No health probes in tests
});

setUp(() async {
  client = $PocketBase.database(
    'http://mock.pb',
    inMemory: true,
    httpClientFactory: () => MockClient((request) async => http.Response('Not Found', 404)),
  );
  await client.syncCompleted;
});

tearDown(() => client.close());
```
