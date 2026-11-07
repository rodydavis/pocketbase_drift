# PocketBase Drift

A powerful, offline-first Flutter client for [PocketBase](https://pocketbase.io), backed by the reactive persistence of [Drift](https://drift.simonbinder.eu).

This library extends the official PocketBase Dart SDK to provide a seamless offline-first experience. It automatically caches data from your PocketBase instance into a local SQLite database, allowing your app to remain fully functional even without a network connection. Changes made while offline are queued and automatically retried when connectivity is restored.

<details>
<summary><h2 style="display: inline;">Table of Contents</h2></summary>

- [Features](#features)
- [Getting Started](#getting-started)
  - [1. Add Dependencies](#1-add-dependencies)
  - [2. Initialize the Client](#2-initialize-the-client)
  - [3. Set the Database Schema (Enable Offline Records)](#3-set-the-database-schema-enable-offline-records)
  - [4. Web Setup](#4-web-setup)
- [Core Concepts](#core-concepts)
  - [RequestPolicy](#requestpolicy)
    - [For Read Operations (GET)](#for-read-operations-get)
    - [For Write Operations (CREATE/UPDATE/DELETE)](#for-write-operations-createupdatedelete)
  - [Choosing the Right Policy](#choosing-the-right-policy)
  - [Global Request Policy](#global-request-policy)
  - [Request Timeout](#request-timeout)
  - [Error Handling](#error-handling)
  - [Offline Support & Sync](#offline-support--sync)
    - [The sync engine](#the-sync-engine)
    - [Concurrent edits and counters](#concurrent-edits-and-counters)
    - [Sync failures](#sync-failures)
    - [Showing pending changes](#showing-pending-changes)
  - [Connectivity Monitoring](#connectivity-monitoring)
- [Usage Examples](#usage-examples)
  - [Fetching Records](#fetching-records)
  - [Reactive Streams](#reactive-streams)
  - [Expanding Relations](#expanding-relations)
    - [Single Relations (maxSelect = 1)](#single-relations-maxselect--1)
    - [Multi Relations (maxSelect > 1)](#multi-relations-maxselect--1)
    - [Nested (Multi-Level) Expansion](#nested-multi-level-expansion)
  - [Creating and Updating Records](#creating-and-updating-records)
  - [Batch Requests](#batch-requests)
  - [Local Full-Text Search](#local-full-text-search)
  - [Local Filters](#local-filters)
  - [File Handling](#file-handling)
    - [File cache size](#file-cache-size)
  - [Custom API Route Caching](#custom-api-route-caching)
  - [Cache TTL & Maintenance](#cache-ttl--maintenance)
    - [Configuration](#configuration)
    - [Running Maintenance](#running-maintenance)
- [Authentication Persistence](#authentication-persistence)
  - [Expired sessions](#expired-sessions)
- [Testing](#testing)
- [Advanced: Direct Database Access](#advanced-direct-database-access)
  - [Database Schema](#database-schema)
  - [Running Raw SQL Queries](#running-raw-sql-queries)
  - [Joining Data Across Collections](#joining-data-across-collections)
  - [Reactive Streams with Raw SQL](#reactive-streams-with-raw-sql)
  - [Executing Raw Statements](#executing-raw-statements)
  - [Using the Built-in Query Builder](#using-the-built-in-query-builder)
- [Credits](#credits)

</details>

## Features

*   **Offline-First Architecture**: Read, create, update, and delete records even without a network connection.
*   **Automatic Synchronization**: Changes made while the server is unreachable are queued and synced when it is reachable again. Rejected changes are kept and reported, never silently deleted.
*   **Reactive Data & UI**: Build reactive user interfaces with streams that automatically update when underlying data changes, whether from a server push or a local mutation.
*   **Local Caching with Drift**: All collections and records are cached in a local SQLite database, providing fast, offline access to your data.
*   **Powerful Local Querying**: Full support for local querying, mirroring the PocketBase API. This includes:
    *   **Filtering**: Complex `filter` strings are parsed into SQLite `WHERE` clauses, supporting:
        - All standard operators (`=`, `!=`, `>`, `>=`, `<`, `<=`, `~`, `!~`)
        - "Any-of" operators for multi-value fields (`?=`, `?!=`, `?>`, `?>=`, `?<`, `?<=`, `?~`, `?!~`)
        - Literal types: strings, numbers, booleans (`true`/`false`), and `null`
        - DateTime macros (`@now`, `@todayStart`, `@todayEnd`, `@yesterday`, `@tomorrow`, etc.) and `@request.auth.id`
        - Field modifiers (`:lower` for case-insensitive, `:length` for array length)
    *   **Sorting**: Sort results by any field with `sort` (e.g., `-created,name`).
    *   **Field Selection**: Limit the returned fields with `fields` for improved performance.
    *   **Pagination**: `limit` and `offset` are fully supported for local data.
*   **Relation Expansion**: Support for expanding single and multi-level relations (e.g., `post.author`) directly from the local cache, with full compatibility for the PocketBase SDK's `record.get<T>()` dot-notation path access.
*   **Full-Text Search**: Integrated Full-Text Search (FTS5) for performing fast, local searches across all your cached record data.
*   **Batch Requests**: Execute multiple create, update, delete, and upsert operations in a single transactional request with offline support.
*   **Authentication Persistence**: User authentication state is persisted locally using `shared_preferences`, keeping users logged in across app sessions.
*   **Cross-Platform Support**: Works across all Flutter-supported platforms, including mobile (iOS, Android), web, and desktop (macOS, Windows, Linux).
*   **File & Image Caching**: Includes a `PocketBaseImageProvider` that caches images in the local database for offline display. The file cache has a size limit (`maxFileCacheBytes`, least recently used files go first, after oversized ones) and never deletes the files of unsynced changes or local-only records.
-   **Robust & Performant**: The database runs in a background isolate, relations are expanded with one query per relation field, record watchers re-run only for writes to their own and expanded collections, and files are downloaded once and shared between concurrent requests.
-   **Cache TTL & Maintenance**: Configurable time-to-live for cached data with automatic cleanup of expired synced records, a file cache size limit and return of free database pages to the file system.

## Getting Started

### 1. Add Dependencies

Add the following packages to your `pubspec.yaml`:

```yaml
dependencies:
  pocketbase_drift: ^0.7.0 # Use the latest version
```

### 2. Initialize the Client

Replace a standard `PocketBase` client with a `$PocketBase.database` client. It's that simple.

```diff
- import 'package:pocketbase/pocketbase.dart';
+ import 'package:pocketbase_drift/pocketbase_drift.dart';

- final client = PocketBase('http://127.0.0.1:8090');
+ final client = $PocketBase.database('http://127.0.0.1:8090');
```

Optional settings include `requestPolicy` (see [Global Request Policy](#global-request-policy)), `requestTimeout` (see [Request Timeout](#request-timeout)), `cacheTtl`, `maxFileCacheBytes` (see [File cache size](#file-cache-size)), `localSyncRetryCount` and the connectivity tuning options.

### 3. Set the Database Schema (Enable Offline Records)

To enable the offline caching functionality for records, you must provide the database schema to the client. This allows the local database to understand your collection structures for validation and relation expansion without needing to contact the server.

First, download your `pb_schema.json` file from the PocketBase Admin UI (`Settings > Export collections`). Then, add it to your project as an asset.

```dart
// 1. Load the schema from your assets
final schema = await rootBundle.loadString('assets/pb_schema.json');

// 2. Initialize the client and set the schema
final client = $PocketBase.database('http://127.0.0.1:8090');
await client.setSchema(schema);
```

Record reads and writes wait for a pending `setSchema`, so an un-awaited `client.setSchema(schema)` does not race the first write. Awaiting it is still recommended: `setSchema` throws when the JSON is not a list of collections.

### 4. Web Setup

For web, you need to follow the instructions for [Drift on the Web](https://drift.simonbinder.eu/web/#drift-wasm) to copy the `sqlite3.wasm` binary and `drift_worker.js` file into your `web/` directory.

1.  Download the latest `sqlite3.wasm` from the [sqlite3.dart releases](https://github.com/simolus3/sqlite3.dart/releases) and the latest `drift_worker.js` from the [drift releases](https://github.com/simolus3/drift/releases).
2.  Place both files directly inside your project's `web/` folder (`web/sqlite3.wasm` and `web/drift_worker.js`).
## Core Concepts

### RequestPolicy

The `RequestPolicy` enum controls how data is fetched and synchronized between local cache and remote server. Choose the policy that best fits your consistency and availability requirements.

All policies follow one rule: **the cache is used only when the server is unreachable.** "Unreachable" means no answer (status 0), a timeout, a socket error, or the status 408, 429 or 5xx. Any other server answer (400, 401, 403, 404) is thrown as `ClientException` with the server status. Cached data never replaces it.

#### For Read Operations (GET):

-   **`RequestPolicy.networkFirst`**: Prioritizes fresh data from the server.
    - Tries to fetch from the remote server first
    - On success, updates the local cache and returns the fresh data
    - When the server is unreachable, falls back to cached data
    - A 4xx answer is thrown. A `getOne` 404 also removes the stale cached copy (unless it has unsynced local changes). A record created offline and not yet synced is returned from the cache.
    - When the server is unreachable and nothing is cached, throws `ClientException` with status 0
    - **Use case**: When you need the freshest data possible, but can accept stale data if the server is unreachable

-   **`RequestPolicy.cacheFirst`**: Prioritizes instant UI response.
    - Returns cached data immediately
    - Fetches from network in the background to update cache for next time
    - When nothing is cached, waits for the server (same rules as `networkFirst`)
    - **Use case**: When UI responsiveness is critical and slightly stale data is acceptable

-   **`RequestPolicy.cacheAndNetwork`** (Default): Balances freshness and availability.
    - For one-time fetches: Same as `networkFirst`
    - For reactive streams (`watchRecords`): Emits cache immediately, then updates with network data
    - **Use case**: General-purpose offline-first behavior

-   **`RequestPolicy.cacheOnly`**: Only reads from local cache, never contacts server.
    - **Use case**: When you only want to work with locally available data

-   **`RequestPolicy.networkOnly`**: Only reads from server, never uses cache.
    - Throws `ClientException` (status 0 when offline)
    - **Use case**: When you absolutely need fresh data and can't accept stale data

#### For Write Operations (CREATE/UPDATE/DELETE):

-   **`RequestPolicy.networkFirst`**: Server is the source of truth (strict consistency).
    - Writes to server first
    - On success, updates local cache
    - On failure, throws `ClientException` (NO cache fallback). When the server is unreachable (no connection, socket error, or `requestTimeout` elapsed), the status is 0 and `originalError` holds the cause. A 502, 503 or 504 answer keeps the server's status.
    - An update of a missing record (404) is thrown; it is not turned into a create
    - **Use case**: When data integrity is critical and you can't risk conflicts (e.g., financial transactions, inventory management)

-   **`RequestPolicy.cacheFirst`**: Local cache is the source of truth (optimistic updates).
    - Writes to cache first, returns success immediately
    - Sends the change to the server in the background when the server is reachable
    - The change stays pending until the server accepts it. A server rejection is not thrown; it counts as a failed sync attempt (see [Sync failures](#sync-failures))
    - **Use case**: When instant UI feedback is critical (e.g., note-taking apps, drafts)

-   **`RequestPolicy.cacheAndNetwork`** (Default): Resilient offline-first.
    - Tries to write to server first
    - On success, updates local cache
    - When the server is unreachable, writes to cache and marks the change as pending for automatic sync
    - When the server rejects the write (for example 400 validation or 403 rule), throws `ClientException` and stores nothing
    - **Use case**: General-purpose offline-first apps that need to work offline

-   **`RequestPolicy.cacheOnly`**: Only writes to cache, marks as `noSync`.
    - Records will NEVER sync to server
    - **Use case**: Local-only data (user preferences, temp data, offline-only features)

-   **`RequestPolicy.networkOnly`**: Only writes to server, throws on failure.
    - Never touches the cache
    - Throws `ClientException`, with the same status rules as `networkFirst`
    - **Use case**: When you need immediate server confirmation

### Choosing the Right Policy

| Scenario | Read Policy | Write Policy |
|----------|-------------|--------------|
| Real-time collaborative app | `networkFirst` | `networkFirst` |
| Offline-first mobile app | `cacheAndNetwork` | `cacheAndNetwork` |
| Instant feedback UI (notes, drafts) | `cacheFirst` | `cacheFirst` |
| Financial transactions | `networkFirst` | `networkFirst` |
| Analytics/telemetry | N/A | `cacheFirst` |
| Local-only settings | `cacheOnly` | `cacheOnly` |

#### Rationale

-   **Real-time**: Uses `networkFirst` to ensure all users see the exact same state (e.g., chat, live editing).
-   **Offline-first**: Uses `cacheAndNetwork` to provide a "it just works" experience, reads fall back to cache if the server is unreachable and writes queue automatically.
-   **Instant Feedback**: Uses `cacheFirst` to make the UI feel instantaneous (e.g., ticking a todo, "liking" a post). The app doesn't wait for the server; it updates the UI immediately and handles the sync silently in the background.
-   **Financial Transactions**: Uses `networkFirst` because the server must validate the transaction before it's confirmed. Unlike `networkOnly`, this automatically updates your local cache on success, ensuring the user sees their new balance immediately without a manual refresh.
-   **Analytics**: Uses `cacheFirst` for non-blocking "fire-and-forget" logging. It returns immediately so it never slows down the UI. The background sync sends the event when the server is reachable. An event that the server rejects is parked and reported on `client.syncFailures`.
-   **Local-only**: Uses `cacheOnly` to keep specific data (like device-specific settings) purely local, ensuring it never attempts to sync to the backend.

### Global Request Policy

Instead of passing a `requestPolicy` to every method call, you can set a global default on the client:

```dart
// Set a global default policy
final client = $PocketBase.database(
  'http://127.0.0.1:8090',
  requestPolicy: RequestPolicy.networkFirst,
);

// All methods will now default to networkFirst
await client.collection('posts').getFullList(); // Uses networkFirst
await client.collection('posts').create(body: {...}); // Uses networkFirst
```

You can still override the global default on a per-call basis:

```dart
// Override for a specific call
await client.collection('posts').getFullList(
  requestPolicy: RequestPolicy.cacheOnly, // Overrides global default
);
```

The resolution order is:
1. **Explicit method parameter** (if provided)
2. **Client's global `requestPolicy`** (defaults to `cacheAndNetwork`)

### Request Timeout

`requestTimeout` (default 15 s) limits single-record reads and writes without file uploads. When the time elapses, the request counts as "server unreachable": offline-first writes are queued and reads fall back to the cache. `null` disables the limit. Uploads have no limit. List reads (`getList`, `getFullList`) use their own `timeout` argument (default 30 s).

```dart
final client = $PocketBase.database(
  'https://your-pb.example.com',
  requestTimeout: const Duration(seconds: 8),
);

final posts = await client.collection('posts').getFullList(
  timeout: const Duration(seconds: 20),
);
```

### Error Handling

Errors from the server and from the network are thrown as `ClientException`:

- `statusCode == 0`: the server is unreachable and the cache cannot answer (nothing cached, or a strict policy such as `networkOnly`).
- 4xx (400, 401, 403, 404): the server's answer. Cached data never replaces it.
- 401 without a request: the session expired and a record read with a cache policy finds nothing in the cache (see [Expired sessions](#expired-sessions)).
- 408, 429, 5xx: the server is busy or down. Offline-first policies use the cache or queue the write; the error reaches you only when the cache cannot answer.

```dart
try {
  final post = await client.collection('posts').getOne(id);
  show(post);
} on ClientException catch (e) {
  if (e.statusCode == 0) {
    showOffline(); // Not reachable and not cached.
  } else if (e.statusCode == 404) {
    showNotFound(); // Deleted on the server; the cached copy was removed.
  } else {
    showError(e.response['message']); // For example 403 from an API rule.
  }
}
```

`getOneOrNull` and `getFirstListItemOrNull` return `null` instead of throwing for a 404 or a cache miss. `cacheOnly` reads of a missing record throw `CacheMissException`.

`getFileBytes` follows the same rule. When the download fails and no cached copy exists, it throws `ClientException` with status 0 for an unreachable server or a timeout (`originalError` holds the cause), or the server's `ClientException` for an HTTP error. A `cacheOnly` cache miss throws `CacheMissException`.

### Offline Support & Sync

Write operations with `cacheAndNetwork` or `cacheFirst` keep working when the server is unreachable:

-   **Server reachable**: `cacheAndNetwork` sends the operation to the server and updates the cache on success. `cacheFirst` writes the cache first and sends the change in the background.
-   **Server unreachable** (no connection, timeout, 408, 429 or 5xx): the operation is applied to the local cache and marked as pending. The change syncs when the server is reachable again.
-   **Server rejects the operation** (for example 400 or 403): `cacheAndNetwork` throws the `ClientException` and stores nothing. With `cacheFirst`, the caller already has the local result; the rejection counts as a failed sync attempt (see below).

Offline deletions are stored as local *tombstones* (`deleted: true`) until the server confirms them. Tombstones are invisible to all local reads (`getFullList`, `getOne`, `watchRecords`, `search`, counts) but remain in the pending queue until synced. A record that was created offline and is deleted before it syncs is removed locally at once; no server delete is queued.

A deletion of a record that is not in the cache is queued too (`cacheAndNetwork` when the server is unreachable; `cacheFirst` always). It is a bare tombstone: the id and the bookkeeping keys only, no record fields. When the server answers 404 at sync time (the record is already gone, or the delete rule does not match), the deletion ends without a `SyncFailure`.

#### The sync engine

`client.syncPendingChanges()` pushes all pending changes to the server. It runs automatically:

- when the client starts,
- when the server becomes reachable,
- when the app resumes,
- after a login or a token refresh (`authRefresh`).

It does nothing while the session is expired (see [Expired sessions](#expired-sessions)).

Only one pass runs at a time. A call during a pass returns a future that completes after one more pass, so changes queued in the meantime are included. The method never throws. `await client.syncCompleted` waits for the running pass.

During a pass:

- Collections sync parents first (by relation fields), so a referenced record exists on the server before the records that point to it.
- Records sync oldest change first.
- An update sends only the fields changed locally. A field changed only with `+`/`-` modifiers is sent as a modifier (see below). A create sends the whole record. New files are sent once as multipart parts; later edits do not upload them again.
- A create whose earlier response was lost (the id already exists on the server) is sent as an update.
- A pending local edit is not overwritten by list refreshes or realtime events: the locally changed fields win until they are synced. A realtime delete keeps a row with pending edits; the sync then gets 404, drops the edit and emits a `SyncFailure` with `dropped == true`.

#### Concurrent edits and counters

A queued update merges with the changes that other devices made to the same record:

- **Other fields**: sync sends only the fields changed locally (`pendingFields`). Server changes to other fields stay.
- **Modifier edits**: when every local edit of a field was a modifier, sync sends the change relative to the server value that the first edit was made on (`pendingBase`). A number sends its difference (`n+: 2`, or `n-` for a negative difference). A multi-value relation, select or file field sends the added values as `f+` (`+f` for prepends) and the removed values as `f-`. Increments, appends, removals and file uploads of other devices stay. The field must be in the collection schema (`setSchema`).
- **Plain sets**: when the pending history of a field has a plain set (`n: 5`, `tags: [...]`), sync sends the absolute value: the last write wins. Single-value relation, select and file fields, JSON fields and text fields always send their absolute value. Pending rows written before 0.7.0 (no `pendingBase`) send absolute values.
- **Online writes**: an online update of a record with a queued edit removes the fields it set from the queue. An online modifier (`n+: 1` with `networkFirst` or `cacheAndNetwork`) of a field with a queued modifier edit keeps both changes.
- **Batches**: a batch update does not mark the queued change of the record as synced. The fields, increments and uploads that the batch did not send still sync. A value that the batch set is not overwritten later by the older queued value. An edit made while an online batch is in flight stays pending, also when it restores the old value.
- **Sent fields**: a field that a push or a batch sent is not sent again when the server stores it in another form (dates) or does not return it (the `password` of an auth record). With a `fields:` projection, the cached record keeps its other fields and queued increments are not lost.
- **Limits**: mixed append and prepend edits are sent as an append. Float differences can have rounding errors.

For counters (likes, stock, views), use the `+`/`-` modifiers. Queued modifier edits merge; plain sets are last-write-wins.

```dart
await client.collection('posts').update(
  postId,
  body: {'likes+': 1, 'tags+': ['flutter']},
  requestPolicy: RequestPolicy.cacheFirst,
);
// Sync sends the total change as modifiers, for example {'likes+': 3} after
// three offline likes, and {'tags+': ['flutter']}.
```

#### Sync failures

When the server rejects a change `localSyncRetryCount` times (default 5), the change is **parked**, not deleted:

- The row stays in the cache with a `syncError` map (`status`, `message`, `data`, `at`).
- A `SyncFailure` is emitted on `client.syncFailures`.
- Automatic sync skips the row.

When an offline update targets a record that was deleted on the server, the local change is dropped. A `SyncFailure` with `dropped == true` is emitted.

```dart
client.syncFailures.listen((failure) {
  if (failure.dropped) {
    // The record was deleted on the server. The local change is gone.
    return;
  }
  print('${failure.collection}/${failure.recordId} '
      '${failure.operation.name} rejected: ${failure.statusCode} ${failure.error}');
});

// After the cause is fixed: retry the parked changes too.
await client.syncPendingChanges(includeFailed: true);

// Or drop the local change. The next read loads the server's version.
await client.discardPendingChange('posts', recordId);
```

For one collection, `client.collection('posts').retryLocal(includeFailed: true)` returns a stream of `RetryProgressEvent`s. `client.collection('posts').pushPending(id)` pushes one record and returns a `PushOutcome` (`synced`, `skipped`, `retryLater` or `rejected`). Pushes and online writes of one record run one at a time: a second push waits for the running one and then sends what is still pending, and a change made while the push is in flight stays pending and syncs next. An online write waits at most `requestTimeout` for a running push of its record; after that, `cacheAndNetwork` queues the write behind the push, and `networkOnly`/`networkFirst` throw `ClientException` with status 0. A sync pass waits at most `requestTimeout` for each record, so a slow upload does not block the other changes.

#### Showing pending changes

`client.db.pendingRecords()` selects the rows with unsynced changes, oldest first. It includes parked rows and excludes local-only rows and rows of other accounts. Use `.watch()` for a live count:

```dart
StreamBuilder<List<Service>>(
  stream: client.db.pendingRecords().watch(),
  builder: (context, snapshot) {
    final pending = snapshot.data ?? const <Service>[];
    final failed =
        pending.where((row) => row.data[RecordMeta.syncError] != null).length;
    return Badge(
      isLabelVisible: pending.isNotEmpty,
      label: Text('${pending.length}'),
      child: Icon(failed > 0 ? Icons.sync_problem : Icons.sync),
    );
  },
);
```

`client.db.pendingRecords(service: 'posts')` limits the result to one collection. `client.collection('posts').pending()` returns the same rows as `RecordModel`s.

- A queued deletion of a record that was not cached is a bare row: it has the id and the bookkeeping keys, but no record fields. Do not expect fields such as `title` in a queue UI.
- Pending updates carry `pendingBase`, `baseUpdated` and `pendingDeltas` in `data` (see [Concurrent edits and counters](#concurrent-edits-and-counters)). `RecordMeta.strip(data)` removes them.
- An open `pendingRecords().watch()` follows an account switch: after a login it shows the rows of the new account without a new listen.

### Connectivity Monitoring

The client ships with a realtime connectivity monitor tuned for PocketBase — not a generic "internet checker" polling external hosts. `ConnectivityService` combines three signals:

1.  **Interface events** (`connectivity_plus`): losing the last network interface marks the app offline instantly; regaining one triggers an immediate probe.
2.  **Server health probes**: the actual PocketBase server is probed (`/api/health`). While online, a slow keepalive probe runs; while offline, probes back off exponentially (5s doubling to 60s by default) so restoration is detected within seconds. **When the server becomes reachable, the pending changes sync automatically.**
3.  **Request outcomes**: real CRUD traffic reports success/failure for instant state flips.

Only connectivity failures count towards "offline": no answer (status 0), timeouts, socket errors and 502/503/504. Two consecutive failures mark the server unreachable. Any other server answer (including 4xx and 500) marks it reachable.

```dart
// Current status and reactive stream
final isOnline = client.connectivity.isConnected;
client.connectivity.statusStream.listen((online) {
  if (online) print('Back online - pending changes will sync');
});

// Offline-first policies use the network only when this is true
// (an interface is up and the server is not known to be down).
client.connectivity.canReachServer;

// Strict policies (networkOnly, networkFirst) try the server while any
// network interface is up.
client.connectivity.shouldAttemptNetwork;
```

`statusStream` gives each new listener the current status first. After that, a listener gets an event only when the status changes.

Tuning (per client):

```dart
final client = $PocketBase.database(
  'https://your-pb.example.com',
  connectivityProbeTimeout: const Duration(seconds: 5),
  connectivityOnlineProbeInterval: const Duration(seconds: 60),
  connectivityOfflineBackoffMin: const Duration(seconds: 5),
  connectivityOfflineBackoffMax: const Duration(seconds: 60),
);
```

Works on all platforms, including web (probes are plain HTTP to your own server, so no CORS issues with third-party check endpoints).

## Usage Examples

### Fetching Records

```dart
// Get a reactive stream of all "posts"
final stream = client.collection('posts').watchRecords();

// Get a one-time list of posts, sorted by creation date
final posts = await client.collection('posts').getFullList(
  sort: '-created',
  requestPolicy: RequestPolicy.cacheAndNetwork, // Explicitly set policy
);

// Watch a single record
final postStream = client.collection('posts').watchRecord('RECORD_ID');

// Get a single record
final post = await client.collection('posts').getOne('RECORD_ID');

// Get a single record, or null when it does not exist
final maybePost = await client.collection('posts').getOneOrNull('RECORD_ID');
final firstDraft = await client.collection('posts').getFirstListItemOrNull('draft = true');

// Watch records with network fetching state (useful to avoid UI flashing)
final stateStream = client.collection('posts').watchRecordsState(
  requestPolicy: RequestPolicy.cacheAndNetwork,
);
stateStream.listen((state) {
  if (state.data.isEmpty && state.isFetchingNetwork) {
    print('Cache is empty, but we are fetching from the network... show a loading spinner!');
  } else {
    print('Data loaded: ${state.data.length} posts');
  }
});
```

### Reactive Streams

`watchRecord`, `watchRecords`, `watchRecordState` and `watchRecordsState` behave as follows:

| Policy | Data source | Server refresh |
|--------|-------------|----------------|
| `cacheOnly` | Cache | Never |
| `cacheFirst` | Cache | Once, when the stream starts |
| `networkFirst`, `cacheAndNetwork` | Cache | When the stream starts, on every realtime event, after a realtime reconnect and when the server becomes reachable again |
| `networkOnly` | Server data (the cache is not used) | When the stream starts and on every realtime event |

- All live queries of a collection share one realtime subscription. Each server event is written to the cache once.
- The realtime connection follows the account: after a login, a logout or an account switch it reconnects with the current token (the app's own `realtime.subscribe` listeners included), and the live queries refetch. PocketBase keeps the auth that a connection had when its subscriptions were sent, so until the reconnect, events of the previous account are dropped and never reach the cache. A token refresh of the same account keeps the connection.
- With `limit`, only `limit` records are fetched from the server (the first page of `sort`), not the whole collection:

  ```dart
  final latest = client.collection('posts').watchRecords(
    sort: '-created',
    limit: 20,
  );
  ```
- An unreachable server is **not** an error for cache-backed queries. They keep the cached data and refresh when the server is back. The stream does not emit an error and `QueryState.error` is not set for it.
- Other fetch errors (for example a 403 from an API rule, or a filter that the cache cannot evaluate) are delivered as stream errors and as `QueryState.error`. The stream stays open. The next successful fetch clears the error.
- A cache-backed stream re-runs its query only for writes to its own collection and to the collections in its `expand` (and, with `expand`, for schema changes). Writes to other collections do not re-run it.
- After a login with another account, open streams change to the data of the new account (pending changes, `@request.auth.id` filters) without a new listen.

### Expanding Relations

The library fully supports relation expansion from the local cache, with full compatibility with the PocketBase SDK's dot-notation path syntax via `record.get<T>()`.

#### Single Relations (maxSelect = 1)

Single relations are returned as objects directly (not wrapped in a list), matching the PocketBase SDK behavior:

```dart
// Fetch a post with its author expanded (single relation)
final post = await client.collection('posts').getOne(
  'RECORD_ID',
  expand: 'author',
);

// Access expanded data directly (no index needed)
final authorName = post.get<String>('expand.author.name');
final authorEmail = post.get<String>('expand.author.email', 'N/A'); // With default

// Get the expanded record as a RecordModel
final author = post.get<RecordModel>('expand.author');
print(author.get<String>('name'));
```

#### Multi Relations (maxSelect > 1)

Multi relations are returned as lists, requiring index-based access:

```dart
// Fetch a post with multiple tags expanded
final post = await client.collection('posts').getOne(
  'RECORD_ID',
  expand: 'tags',
);

// Access by index
final firstTag = post.get<String>('expand.tags.0.name');
final secondTag = post.get<String>('expand.tags.1.name');

// Or get all as a list and iterate
final tags = post.get<List<RecordModel>>('expand.tags');
for (final tag in tags) {
  print(tag.get<String>('name'));
}
```

#### Nested (Multi-Level) Expansion

You can expand multiple levels of relations and access deeply nested data:

```dart
// Expand nested relations: post -> author -> profile (all single relations)
final post = await client.collection('posts').getOne(
  'RECORD_ID',
  expand: 'author.profile',
);

// Access deeply nested fields (no index for single relations)
final bio = post.get<String>('expand.author.expand.profile.bio');
final avatar = post.get<String>('expand.author.expand.profile.avatar');
```

> **Note**: This works identically whether the data comes from the network or the local cache, ensuring a consistent API across online and offline scenarios.

### Creating and Updating Records

```dart
// Create a new record (works online and offline)
final newRecord = await client.collection('posts').create(
  body: {
    'title': 'My Offline Post',
    'content': 'This was created without a connection.',
  },
  requestPolicy: RequestPolicy.cacheAndNetwork,
);

// Update a record
await client.collection('posts').update(newRecord.id, body: {
  'content': 'The content has been updated.',
});
```

### Batch Requests

Batch requests allow you to execute multiple create, update, delete, and upsert operations in a single transactional HTTP request. This is more efficient than individual requests and ensures atomicity on the server.

```dart
// Create a batch instance
final batch = client.$createBatch();

// Queue operations across multiple collections
batch.collection('posts').create(body: {
  'title': 'New Post',
  'content': 'Created in a batch',
});

batch.collection('posts').update('abc123', body: {
  'title': 'Updated Title',
});

batch.collection('comments').delete('def456');

// Upsert: creates if ID doesn't exist, updates if it does
batch.collection('tags').upsert(body: {
  'id': 'tag_flutter',
  'name': 'Flutter',
});

// Send all operations in a single request
final results = await batch.send(
  requestPolicy: RequestPolicy.cacheAndNetwork,
);

// Check results
for (final result in results) {
  if (result.isSuccess) {
    print('${result.collection}: Success');
    final record = result.record; // Access the returned RecordModel
  } else {
    print('${result.collection}: Failed with status ${result.status}');
  }
}
```

**Record ids**: creates and upserts without an `id` get a client-generated id. A retried batch or a later offline sync therefore cannot create duplicates.

**Files**: the `files` passed to `create`, `update` and `upsert` are sent with the batch. When the batch is queued offline, the files are stored and sent when the operations sync.

**Errors and offline behaviour**:
- `cacheAndNetwork` (default): when the server is unreachable, all operations are stored locally as pending. They sync as individual operations later. A queued delete of a record that is not cached returns status 204, like a cached one. When the server rejects the batch (for example a validation error), `send` throws `ClientException` and nothing is stored.
- `networkFirst`: the server must accept the batch; then the cache is updated. Offline, `send` throws `ClientException` with status 0.
- `networkOnly`: like `networkFirst`, but the cache is not updated. Exception: a record with a queued local change is updated, so the queue does not send an older value of a field that the batch set.
- `cacheFirst`: the operations are written to the cache as pending and the batch is sent in the background. If the server rejects the batch, the operations sync individually.
- `cacheOnly`: the operations are written to the cache as local-only (`noSync`).

**Queued changes**: a batch update of a record with an unsynced local change does not mark the whole change as synced. The fields, increments and uploads that the batch did not send still sync. A value that the batch set is not overwritten later by the older queued value. An edit made while an online batch is in flight stays pending, also when it restores the old value. A field that the batch sent is done also when the server stores it in another form (dates) or does not return it (`password`).

### Local Full-Text Search

```dart
// Search all fields in the 'posts' collection for the word "flutter"
final results = await client.collection('posts').search('flutter').get();

// Search across all collections
final globalResults = await client.search('flutter').get();
```

The index holds the record JSON without the sync bookkeeping keys (`pendingBase`, `pendingFields`, ...). A record with a pending local edit is found by its new value, not by its old one.

### Local Filters

Cache reads translate the PocketBase `filter` string to SQL. The local parser follows the PocketBase rules:

- **Operators**: `=`, `!=`, `>`, `>=`, `<`, `<=`, `~`, `!~` and the any-of forms `?=`, `?!=`, `?>`, `?>=`, `?<`, `?<=`, `?~`, `?!~`. `~` and `!~` escape `%` and `_` like the server.
- **Logical operators**: `&&`, `||` and parentheses. `//` comments are removed.
- **Strings**: `"..."` or `'...'` with the PocketBase escapes `\"`, `\'`, `\\`, `\n`, `\t`, `\r`. Values built with `client.filter('title = {:t}', {'t': value})` match the same records locally and on the server.
- **Other literals**: numbers, `true`, `false`, `null`.
- **Date macros** (UTC, formatted like PocketBase dates, e.g. `2026-11-04 00:00:00.000Z`): `@now`, `@todayStart`, `@todayEnd`, `@yesterday` and `@tomorrow` (now ± 1 day), `@monthStart`, `@monthEnd`, `@yearStart`, `@yearEnd`, and the numbers `@second`, `@minute`, `@hour`, `@day`, `@weekday` (0 = Sunday), `@month`, `@year`.
- **`@request.auth.id`**: the id of the logged-in account (`client.authStore.record?.id`), or `""` when nobody is logged in, like the server.
- **Field modifiers**: `:lower`, `:length`.

The cache cannot evaluate other `@request.*` values, `@collection.*`, field references on the right-hand side, or `@` tokens on the left-hand side. A local read with such a filter throws `UnsupportedError`. A malformed filter throws `FormatException`. Use `networkOnly` for filters that the cache cannot evaluate.

```dart
// Works offline: literals, date macros and @request.auth.id.
final mine = await client.collection('tasks').getFullList(
  filter: 'owner = @request.auth.id && due >= @todayStart',
);

// The cache cannot evaluate @collection: ask the server only.
final shared = await client.collection('tasks').getFullList(
  filter: '@collection.members.user ?= owner',
  requestPolicy: RequestPolicy.networkOnly,
);
```

### File Handling

The library automatically caches files for offline use.

```dart
// Use the included PocketBaseImageProvider for easy display
Image(
  image: PocketBaseImageProvider(
    client: client,
    recordId: postRecord.id,
    recordCollectionName: postRecord.collectionName,
    filename: postRecord.get<String>('my_image_field'), // The filename
    thumb: '400x0', // Optional: PocketBase thumb, resized by the server
    pixelWidth: 400, // Optional: decode size in physical pixels
  ),
);

// Or get the file bytes directly
final bytes = await client.files.getFileBytes(
  recordId: postRecord.id,
  recordCollectionName: postRecord.collectionName,
  filename: postRecord.get<String>('my_image_field'),
  thumb: '100x100', // Optional
  timeout: const Duration(seconds: 30), // Default
  requestPolicy: RequestPolicy.cacheAndNetwork,
);
```

`getFileBytes`:
- Returns a non-expired cached copy without a network request.
- With `cacheOnly`, never downloads. Returns a cached copy even when it is expired, and throws `CacheMissException` when there is none.
- With every other policy (including `cacheFirst`), downloads when there is no cached copy or the copy is expired.
- When the download fails or exceeds `timeout` (default 30 s), returns an expired cached copy if one exists. Else it throws.
- Throws `ClientException` (with status, URL and response) when the server answers with a status other than 200.
- Caches each `thumb` separately from the original file.
- Shares one download between concurrent calls for the same file and thumb (`client.files` is one instance per client).
- `expireAfter` sets how long a cached copy is fresh. An expired copy is downloaded again when the server is reachable and is still used offline. `runMaintenance()` with a TTL deletes expired copies; the size limit below deletes the least recently used copies.

`PocketBaseImageProvider`:
- Takes the same `thumb`, `token`, `requestPolicy`, `expireAfter` and `timeout` options as `getFileBytes`.
- Decode size: with `pixelWidth` and/or `pixelHeight`, the image is decoded at the smallest size that covers the box and keeps the aspect ratio. It is never enlarged. Without them, `size` (logical pixels) × device pixel ratio is used. Without any of them, the image is decoded at full size.
- Has value equality: providers with the same inputs are equal and share one `ImageCache` entry. Creating a new provider in every `build` does not load the image again.
- Evicts a failed load from the `ImageCache`, so the next build tries again.

To save memory, request a server thumb with `thumb` and set a decode size.

#### File cache size

`maxFileCacheBytes` limits the size of the file blob cache: downloaded files, thumbs and the cached copies of uploads. The default is `$PocketBase.defaultMaxFileCacheBytes`: 128 MB, 32 MB on the web (the IndexedDB storage fallback keeps the whole database in memory). `null` disables the limit.

```dart
final client = $PocketBase.database(
  'https://example.pocketbase.io',
  maxFileCacheBytes: 256 * 1024 * 1024, // 256 MB; null = no limit
);
```

- After each blob write (a download or the cached copy of an upload), eviction runs in the background. One run at a time. It deletes blobs until the cache holds at most 90% of the limit (the eviction target): first the blobs larger than the target, then the least recently used ones.
- A cache hit marks a blob as used, at most once per hour per blob. A file that the server renamed after a push counts as used now. Blobs cached before the upgrade to 0.7.0 have no last-use time and are evicted first.
- The blobs of pending and local-only (`noSync`) records are never deleted: they are the only copy. This includes the pending uploads of another account. The blobs of a record deleted with `cacheOnly` can be deleted. When the pinned blobs alone keep the cache above the limit, eviction pauses until the cache grows by 10% of the limit or a sync pass ends.
- A file larger than 90% of the limit is returned but not cached: downloads, and the copies of uploads that the server accepted. Unsynced uploads are always stored. `client.fitsFileCache(bytes)` tells if a file of that size goes into the cache.
- `client.enforceFileCacheLimit()` applies the limit now. `client.db.fileCacheBytes()` returns the cache size in bytes. `runMaintenance()` also applies the limit (see [Running Maintenance](#running-maintenance)).
- Write blobs only through `client.db.setFile`. It also writes the size and last use of the blob (table `BlobFileStats`). A blob inserted into `BlobFiles` with raw SQL has no stats row: the limit does not count it and never evicts it.

### Custom API Route Caching

The library supports offline caching for custom API routes accessed via the `send` method. This is particularly useful for `GET` requests to custom endpoints that return data you want available offline.

To use it, simply call the `send` method on your `$PocketBase` client and provide a `RequestPolicy`.

**Note:** Caching is only applied to `GET` requests by default to prevent unintended side effects from caching state-changing operations (`POST`, `DELETE`, etc.).

```dart
// This request will be cached and available offline.
try {
  final customData = await client.send(
    '/api/my-custom-route',
    requestPolicy: RequestPolicy.cacheAndNetwork, // Use the desired policy
  );
} on ClientException catch (e) {
  // statusCode 0: server unreachable and no cached response.
  // 4xx: the server's answer (cached data is not used for it).
}

// This POST request will bypass the cache and go directly to the network.
await client.send(
  '/api/submit-form',
  method: 'POST',
  body: {'name': 'test'},
  // No requestPolicy needed, but even if provided, it would be ignored.
);
```

### Cache TTL & Maintenance

The library supports configurable cache expiration to prevent the local database from growing indefinitely. You can configure a time-to-live (TTL) for cached data and run periodic maintenance to clean up old entries.

#### Configuration

Set the `cacheTtl` when initializing the client (default is 60 days):

```dart
final client = $PocketBase.database(
  'https://example.pocketbase.io',
  cacheTtl: Duration(days: 30), // Custom TTL: 30 days
);

// Or disable TTL expiry (keep records forever). runMaintenance() still
// applies maxFileCacheBytes and returns free pages to the file system.
final clientNoExpiry = $PocketBase.database(
  'https://example.pocketbase.io',
  cacheTtl: null,
);
```

#### Running Maintenance

Call `runMaintenance()` to clean up expired cached data, apply the file cache size limit and return free database pages to the file system. This is typically done on app startup or periodically:

```dart
// Run maintenance with the configured TTL
final result = await client.runMaintenance();
print('Cleaned up ${result.totalDeleted} expired items');

// Or run with a one-time custom TTL
await client.runMaintenance(ttl: Duration(days: 7));
```

The `MaintenanceResult` provides details on what was cleaned up:
- `deletedRecords` - Number of expired synced records deleted
- `deletedResponses` - Number of expired cached API responses deleted
- `deletedFiles` - Number of file blobs deleted: blobs past their expiration, and blobs of records that are no longer cached
- `evictedFiles` - Number of least recently used file blobs deleted to apply `maxFileCacheBytes`
- `evictedBytes` - Bytes of the blobs counted in `evictedFiles`
- `totalDeleted` - Total items cleaned up (`evictedFiles` included)

A record expires by the time it was **cached** (`cachedAt`), not by the server's `updated` value. Every write from the server (single reads, list reads, realtime events) and every local change sets `cachedAt`. A record that the app fetches regularly therefore does not expire, even if nobody edits it on the server.

With `cacheTtl: null` (and no `ttl` argument), the expiry steps are skipped. The other steps always run:

- The file cache size limit (`maxFileCacheBytes`) is applied. See [File cache size](#file-cache-size).
- Up to 4096 free database pages (about 16 MB) are returned to the file system with `PRAGMA incremental_vacuum`. Maintenance never runs a full `VACUUM`.

New databases use `auto_vacuum = INCREMENTAL`. A database created before 0.7.0 does not; it gets smaller only with `client.db.compact(full: true)`. This runs a full `VACUUM`: it can take seconds and needs free disk space of about the size of the database. Run it once, for example after an update, at a quiet moment:

```dart
final released = await client.db.compact(full: true); // number of pages
```

**Important**: Maintenance only deletes **synced** data. Unsynced local changes, local-only records (`noSync: true`), and pending deletions are **never** removed, ensuring you never lose data that hasn't been synced to the server. The file blobs of these records are never evicted.

## Authentication Persistence

The library provides a specialized `$AuthStore` that integrates with `shared_preferences` to persist authentication state across app sessions.

By default (`clearOnLogout: true`), logout (`authStore.clear()`) deletes the cached data, the cached responses and the file blobs. It keeps the schema and the **unsynced local changes**:

- Each pending change belongs to the account that made it (`pendingOwner`).
- While another account (or nobody) is logged in, these rows are hidden from reads, search and sync. A local update or delete of such a record throws `StateError`.
- When the owner logs in again, the rows reappear and sync automatically.

To discard unsynced changes too (for example on a shared device), call `client.db.clearAllData()` after logout. It deletes everything except the schema.

Set `clearOnLogout: false` to keep all cached data on logout:

```dart
final prefs = await SharedPreferences.getInstance();

// Create auth store that preserves data on logout
final authStore = $AuthStore.prefs(
  prefs, 
  'pb_auth', 
  clearOnLogout: false, // Default is true
);

final client = $PocketBase.database(
  'https://example.pocketbase.io',
  authStore: authStore,
);
```

`client.db.clearCache()` gives the same result as a logout with `clearOnLogout: true`. `client.db.clearCache(keepPending: false)` is the same as `clearAllData()`.

### Expired sessions

PocketBase answers a request with an expired auth token as a guest. List rules such as `owner = @request.auth.id` return no rows, and reads, updates and deletes of the account's records get 404. Such answers are not the account's data, so while `client.hasExpiredSession` is `true` (the auth store has a token whose `exp` has passed, the rule of `authStore.isValid`), the package treats the server like an unreachable one for cache-backed work:

- Sync pauses. Queued changes stay pending; nothing is dropped or counted as a rejection. `pushPending` returns `PushOutcome.retryLater`.
- Live queries (`watchRecords`, `watchRecord`, …) keep showing the cache and do not refresh.
- Record reads with `cacheFirst`, `networkFirst` or `cacheAndNetwork` answer from the cache without a request. When nothing is cached, they throw `ClientException` with status 401.
- `cacheAndNetwork` writes and batches are queued. `cacheFirst` writes wait in the queue.
- `networkOnly` and `networkFirst` writes still go to the server. A 404 then does not remove the cached record.

An auth change that leaves a valid token (a login, `authRefresh`) resumes the work: queued changes sync and the paused live queries refresh. Without a token (a guest) nothing pauses. A realtime connection that reconnected while the session was expired is a guest connection; the login reconnects it with the new token.

`client.onSessionExpired` emits when the package first pauses work, and again only after a valid login. A pause while no one listens is not reported, so also check `hasExpiredSession` when you start listening:

```dart
if (client.hasExpiredSession) showLogin();
client.onSessionExpired.listen((_) => showLogin());
```

A token that the server stops accepting before its expiry (password change, deleted account) still looks valid on the device, and the server answers as a guest. Check the session at start and on resume with `authRefresh()`, and log out when it fails with 401.

## Testing

- Use `$PocketBase.database(url, inMemory: true)` for an in-memory database.
- In widget tests, create the client outside the fake-async zone (for example in `setUp`, not in the `testWidgets` body).
- In `setUp`, `await client.syncCompleted`. The client starts a sync pass when it is created. A database query that still runs on real time blocks the queries of the fake-async zone.
- With a mock server, log in with a JWT whose `exp` is in the future. A token that is not a JWT counts as an expired session, so sync and refreshes pause.

## Advanced: Direct Database Access

For advanced use cases like custom SQL queries, complex joins, or direct table inspection, you can access the underlying Drift database directly via `client.db`.

### Database Schema

All PocketBase records are stored in a generic `services` table with the following structure:

| Column | Type | Description |
|--------|------|-------------|
| `id` | TEXT | Record ID (PocketBase ID) |
| `service` | TEXT | Collection name (e.g., "posts", "users") |
| `data` | TEXT | JSON-encoded record data, plus the bookkeeping keys listed in `RecordMeta` |
| `created` | TEXT | ISO 8601 timestamp |
| `updated` | TEXT | ISO 8601 timestamp |
| `cachedAt` | INTEGER | Unix time (seconds) when the row was last written from the server or by a local change (used by the cache TTL) |

**Primary Key**: `(id, service)`. **Index**: `idx_services_service` on `service`.

Additional tables:
- `BlobFiles` - Cached file/image blobs: `id`, `recordId`, `filename`, `data`, `expiration`, `created`, `updated` (unchanged from 0.6.0). Index `idx_blob_files_record` on `recordId, filename`.
- `BlobFileStats` - Size and last use of each blob for the file cache limit: `fileId` (`BlobFiles.id`, primary key), `size` (bytes) and `lastAccess` (last write or cache hit; `null` for blobs cached before 0.7.0). Index `idx_blob_file_stats_access` on `lastAccess, size`. The trigger `blob_files_delete` deletes the stats row when its blob is deleted. Only `client.db.setFile` writes a stats row: a blob inserted with raw SQL is never evicted.
- `CachedResponses` - Cached API responses for custom routes
- `text_entries` - Full-text search index (FTS5) of the record JSON without the sync bookkeeping keys (`synced`, `isNew`, `deleted` and `noSync` stay). The triggers on `services` keep it current. Do not run the FTS5 `rebuild` command: it would index the raw JSON, bookkeeping included.

The bookkeeping keys in `data` are `synced`, `isNew`, `deleted`, `noSync`, `retryCount`, `pendingFields`, `pendingFiles`, `pendingOwner`, `pendingRev`, `syncError`, `pendingBase`, `baseUpdated` and `pendingDeltas`. Use the `RecordMeta` constants instead of string literals. `RecordMeta.isPending(data)` tells if a row holds an unsynced change. `RecordMeta.strip(data)` returns a copy without the bookkeeping keys.

On mobile and desktop, the database runs SQLite in a background isolate (`NativeDatabase.createInBackground`, WAL mode, `journal_size_limit` 8 MB), so queries do not block the UI isolate. A database with `inMemory: true` runs on the calling isolate.

### Running Raw SQL Queries

Use `customSelect` for queries that return data:

```dart
// Simple query - get all posts
final results = await client.db.customSelect(
  "SELECT * FROM services WHERE service = 'posts'",
).get();

// Query with JSON extraction
final posts = await client.db.customSelect('''
  SELECT 
    id,
    json_extract(data, '\$.title') as title,
    json_extract(data, '\$.author') as author,
    created
  FROM services 
  WHERE service = 'posts'
    AND json_extract(data, '\$.published') = 1
  ORDER BY created DESC
  LIMIT 10
''').get();

// Access results
for (final row in posts) {
  print('${row.read<String>('title')} by ${row.read<String>('author')}');
}
```

### Joining Data Across Collections

Since all collections share the same table, you can join them using SQL:

```dart
final results = await client.db.customSelect('''
  SELECT 
    p.id as post_id,
    json_extract(p.data, '\$.title') as post_title,
    json_extract(u.data, '\$.name') as author_name
  FROM services p
  JOIN services u 
    ON json_extract(p.data, '\$.author') = u.id 
    AND u.service = 'users'
  WHERE p.service = 'posts'
''').get();
```

### Reactive Streams with Raw SQL

Use `.watch()` instead of `.get()` for reactive updates:

```dart
// Stream that updates when data changes
final stream = client.db.customSelect(
  "SELECT * FROM services WHERE service = 'posts'",
  readsFrom: {client.db.services}, // Required for reactivity
).watch();

stream.listen((rows) {
  print('Posts updated: ${rows.length} items');
});
```

A query with `readsFrom: {client.db.services}` re-runs on every write to any collection. The package's own record watchers (`watchRecords`, `$query(...).watch()`) re-run only for writes to their own and expanded collections.

### Executing Raw Statements

For INSERT, UPDATE, DELETE operations, use `customStatement`:

```dart
await client.db.customStatement(
  "DELETE FROM services WHERE service = 'temp_data'",
);
// customStatement does not notify streams. Tell drift that `services`
// changed, so open record watchers re-run:
client.db.markTablesUpdated({client.db.services});
```

Or use `customUpdate` with `updates`, which notifies the streams itself:

```dart
await client.db.customUpdate(
  "DELETE FROM services WHERE service = 'temp_data'",
  updates: {client.db.services},
);
```

Raw writes are not tagged with a collection, so they re-run all record watchers. Raw writes do not queue changes for sync. Note that a raw `DELETE FROM services` also deletes unsynced changes.

### Using the Built-in Query Builder

For simpler queries, you can also use the built-in `$query` method which handles JSON extraction automatically:

```dart
// Uses PocketBase-style filter syntax internally
final posts = await client.db.$query(
  'posts',
  filter: "published = true && author != ''",
  sort: '-created',
  limit: 10,
).get();
```

## Credits
 
- [Rody Davis](https://github.com/rodydavis) (Original Creator)
