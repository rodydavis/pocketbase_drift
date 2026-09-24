# PocketBase Drift

A powerful, offline-first Flutter client for [PocketBase](https://pocketbase.io), backed by the reactive persistence of [Drift](https://drift.simonbinder.eu).

This library extends the official PocketBase Dart SDK to provide a seamless offline-first experience. It automatically caches data from your PocketBase instance into a local SQLite database, allowing your app to remain fully functional even without a network connection. Changes made while offline are queued and automatically retried when connectivity is restored.

<details>
<summary><h2 style="display: inline;">Table of Contents</h2></summary>

- [Features](#features)
- [Getting Started](#getting-started)
  - [1. Add Dependencies](#1-add-dependencies)
  - [2. Initialize the Client](#2-initialize-the-client)
  - [3. Cache the Database Schema (Enable Offline Records)](#3-cache-the-database-schema-enable-offline-records)
  - [4. Web Setup](#4-web-setup)
- [Core Concepts](#core-concepts)
  - [RequestPolicy](#requestpolicy)
    - [For Read Operations (GET)](#for-read-operations-get)
    - [For Write Operations (CREATE/UPDATE/DELETE)](#for-write-operations-createupdatedelete)
  - [Choosing the Right Policy](#choosing-the-right-policy)
  - [Global Request Policy](#global-request-policy)
  - [Offline Support & Sync](#offline-support--sync)
- [Usage Examples](#usage-examples)
  - [Fetching Records](#fetching-records)
  - [Expanding Relations](#expanding-relations)
    - [Single Relations (maxSelect = 1)](#single-relations-maxselect--1)
    - [Multi Relations (maxSelect > 1)](#multi-relations-maxselect--1)
    - [Nested (Multi-Level) Expansion](#nested-multi-level-expansion)
  - [Creating and Updating Records](#creating-and-updating-records)
  - [Batch Requests](#batch-requests)
  - [Local Full-Text Search](#local-full-text-search)
  - [File Handling](#file-handling)
  - [Custom API Route Caching](#custom-api-route-caching)
  - [Cache TTL & Maintenance](#cache-ttl--maintenance)
    - [Configuration](#configuration)
    - [Running Maintenance](#running-maintenance)
- [Authentication Persistence](#authentication-persistence)
- [Advanced: Direct Database Access](#advanced-direct-database-access)
  - [Database Schema](#database-schema)
  - [Running Raw SQL Queries](#running-raw-sql-queries)
  - [Joining Data Across Collections](#joining-data-across-collections)
  - [Reactive Streams with Raw SQL](#reactive-streams-with-raw-sql)
  - [Executing Raw Statements](#executing-raw-statements)
  - [Using the Built-in Query Builder](#using-the-built-in-query-builder)
- [TODO](#todo)
- [Credits](#credits)

</details>

## Features

*   **Offline-First Architecture**: Read, create, update, and delete records even without a network connection.
*   **Automatic Synchronization**: Changes made while offline are automatically queued and retried when network connectivity is restored.
*   **Reactive Data & UI**: Build reactive user interfaces with streams that automatically update when underlying data changes, whether from a server push or a local mutation.
*   **Local Caching with Drift**: All collections and records are cached in a local SQLite database, providing fast, offline access to your data.
*   **Powerful Local Querying**: Full support for local querying, mirroring the PocketBase API. This includes:
    *   **Filtering**: Complex `filter` strings are parsed into SQLite `WHERE` clauses, supporting:
        - All standard operators (`=`, `!=`, `>`, `>=`, `<`, `<=`, `~`, `!~`)
        - "Any-of" operators for multi-value fields (`?=`, `?!=`, `?>`, `?>=`, `?<`, `?<=`, `?~`, `?!~`)
        - Literal types: strings, numbers, booleans (`true`/`false`), and `null`
        - DateTime macros (`@now`, `@todayStart`, `@todayEnd`, `@yesterday`, `@tomorrow`, etc.)
        - Field modifiers (`:lower` for case-insensitive, `:length` for array length)
    *   **Sorting**: Sort results by any field with `sort` (e.g., `-created,name`).
    *   **Field Selection**: Limit the returned fields with `fields` for improved performance.
    *   **Pagination**: `limit` and `offset` are fully supported for local data.
*   **Relation Expansion**: Support for expanding single and multi-level relations (e.g., `post.author`) directly from the local cache, with full compatibility for the PocketBase SDK's `record.get<T>()` dot-notation path access.
*   **Full-Text Search**: Integrated Full-Text Search (FTS5) for performing fast, local searches across all your cached record data.
*   **Batch Requests**: Execute multiple create, update, delete, and upsert operations in a single transactional request with offline support.
*   **Authentication Persistence**: User authentication state is persisted locally using `shared_preferences`, keeping users logged in across app sessions.
*   **Cross-Platform Support**: Works across all Flutter-supported platforms, including mobile (iOS, Android), web, and desktop (macOS, Windows, Linux).
*   **File & Image Caching**: Includes a `PocketBaseImageProvider` that caches images in the local database for offline display.
-   **Robust & Performant**: Includes optimizations for batching queries and file streaming on all platforms to handle large files efficiently.
-   **Cache TTL & Maintenance**: Configurable time-to-live for cached data with automatic cleanup of expired synced records.

## Getting Started

### 1. Add Dependencies

Add the following packages to your `pubspec.yaml`:

```yaml
dependencies:
  pocketbase_drift: ^0.6.0 # Use the latest version
```

### 2. Initialize the Client

Replace a standard `PocketBase` client with a `$PocketBase.database` client. It's that simple.

```diff
- import 'package:pocketbase/pocketbase.dart';
+ import 'package:pocketbase_drift/pocketbase_drift.dart';

- final client = PocketBase('http://127.0.0.1:8090');
+ final client = $PocketBase.database('http://127.0.0.1:8090');
```

### 3. Set the Database Schema (Enable Offline Records)

To enable the offline caching functionality for records, you must provide the database schema to the client. This allows the local database to understand your collection structures for validation and relation expansion without needing to contact the server.

First, download your `pb_schema.json` file from the PocketBase Admin UI (`Settings > Export collections`). Then, add it to your project as an asset.

```dart
// 1. Load the schema from your assets
final schema = await rootBundle.loadString('assets/pb_schema.json');

// 2. Initialize the client and set the schema
final client = $PocketBase.database('http://127.0.0.1:8090')
  ..setSchema(schema);
```

### 4. Web Setup

For web, you need to follow the instructions for [Drift on the Web](https://drift.simonbinder.eu/web/#drift-wasm) to copy the `sqlite3.wasm` binary and `drift_worker.js` file into your `web/` directory.

1.  Download the latest `sqlite3.wasm` from the [sqlite3.dart releases](https://github.com/simolus3/sqlite3.dart/releases) and the latest `drift_worker.js` from the [drift releases](https://github.com/simolus3/drift/releases).
2.  Place both files directly inside your project's `web/` folder (`web/sqlite3.wasm` and `web/drift_worker.js`).
## Core Concepts

### RequestPolicy

The `RequestPolicy` enum controls how data is fetched and synchronized between local cache and remote server. Choose the policy that best fits your consistency and availability requirements.

#### For Read Operations (GET):

-   **`RequestPolicy.networkFirst`**: Prioritizes fresh data from the server.
    - Tries to fetch from the remote server first
    - On success, updates the local cache and returns the fresh data
    - On failure (network error or offline), falls back to cached data
    - **Use case**: When you need the freshest data possible, but can accept stale data if network fails

-   **`RequestPolicy.cacheFirst`**: Prioritizes instant UI response.
    - Returns cached data immediately
    - Fetches from network in the background to update cache for next time
    - **Use case**: When UI responsiveness is critical and slightly stale data is acceptable

-   **`RequestPolicy.cacheAndNetwork`** (Default): Balances freshness and availability.
    - For one-time fetches: Same as `networkFirst` (tries network, falls back to cache)
    - For reactive streams (`watchRecords`): Emits cache immediately, then updates with network data
    - **Use case**: General-purpose offline-first behavior

-   **`RequestPolicy.cacheOnly`**: Only reads from local cache, never contacts server.
    - **Use case**: When you only want to work with locally available data

-   **`RequestPolicy.networkOnly`**: Only reads from server, never uses cache.
    - Throws an exception if network is unavailable
    - **Use case**: When you absolutely need fresh data and can't accept stale data

#### For Write Operations (CREATE/UPDATE/DELETE):

-   **`RequestPolicy.networkFirst`**: Server is the source of truth (strict consistency).
    - Writes to server first
    - On success, updates local cache
    - On failure, throws an error (NO cache fallback)
    - **Use case**: When data integrity is critical and you can't risk conflicts (e.g., financial transactions, inventory management)

-   **`RequestPolicy.cacheFirst`**: Local cache is the source of truth (optimistic updates).
    - Writes to cache first, returns success immediately
    - Attempts server sync in the background
    - If background sync fails, the record is marked as "pending sync" and will retry later
    - **Use case**: When instant UI feedback is critical (e.g., note-taking apps, drafts)

-   **`RequestPolicy.cacheAndNetwork`** (Default): Resilient offline-first.
    - Tries to write to server first
    - On success, updates local cache
    - On failure, writes to cache and marks as "pending sync" for automatic retry
    - **Use case**: General-purpose offline-first apps that need to work offline

-   **`RequestPolicy.cacheOnly`**: Only writes to cache, marks as `noSync`.
    - Records will NEVER sync to server
    - **Use case**: Local-only data (user preferences, temp data, offline-only features)

-   **`RequestPolicy.networkOnly`**: Only writes to server, throws on failure.
    - Never touches the cache
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
-   **Offline-first**: Uses `cacheAndNetwork` to provide a "it just works" experience, reads fall back to cache if offline and writes queue automatically.
-   **Instant Feedback**: Uses `cacheFirst` to make the UI feel instantaneous (e.g., ticking a todo, "liking" a post). The app doesn't wait for the server; it updates the UI immediately and handles the sync silently in the background.
-   **Financial Transactions**: Uses `networkFirst` because the server must validate the transaction before it's confirmed. Unlike `networkOnly`, this automatically updates your local cache on success, ensuring the user sees their new balance immediately without a manual refresh.
-   **Analytics**: Uses `cacheFirst` for non-blocking "fire-and-forget" logging. It returns immediately so it never slows down the UI, while the background sync guarantees the event inevitably reaches the server even if the user is offline at that moment.
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

### Offline Support & Sync

When using `cacheAndNetwork` or `cacheFirst` policies for write operations, the library automatically handles network failures:

-   **When Online**: Operations are sent to the server. On success, local cache is updated.
-   **When Offline** (or network failure):
    - `cacheAndNetwork`: Operation is applied to local cache and marked as "pending sync"
    - `cacheFirst`: Operation succeeds locally, background sync is attempted
    - In both cases, the UI responds instantly and the change will automatically sync when connectivity is restored

Offline deletions are stored as local *tombstones* (`deleted: true`) until the server confirms them. Tombstones are invisible to all local reads (`getFullList`, `getOne`, `watchRecords`, `search`, counts) but remain in the pending queue until synced. A record that was created offline and deleted before ever syncing is purged locally during sync — no doomed server round-trip.

### Connectivity Monitoring

The client ships with a realtime connectivity monitor tuned for PocketBase — not a generic "internet checker" polling external hosts. `ConnectivityService` combines three signals:

1.  **Interface events** (`connectivity_plus`): losing the last network interface marks the app offline instantly; regaining one triggers an immediate probe.
2.  **Server health probes**: the actual PocketBase server is probed (`/api/health`). While online, a slow keepalive probe runs; while offline, probes back off exponentially (5s doubling to 60s by default) so restoration is detected within seconds. **A successful probe or request triggers the pending-sync retry automatically.**
3.  **Request outcomes**: real CRUD traffic reports success/failure for instant state flips.

```dart
// Current status and reactive stream
final isOnline = client.connectivity.isConnected;
client.connectivity.statusStream.listen((online) {
  if (online) print('Back online - pending changes will sync');
});

// Whether writes should attempt the network
client.connectivity.shouldAttemptNetwork;
```

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

**Offline Behavior**: When using `RequestPolicy.cacheAndNetwork` (default) and the batch request fails due to network issues, all operations are stored locally and marked as pending. They will be retried as individual operations when connectivity is restored.

### Local Full-Text Search

```dart
// Search all fields in the 'posts' collection for the word "flutter"
final results = await client.collection('posts').search('flutter').get();

// Search across all collections
final globalResults = await client.search('flutter').get();
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
    filename: postRecord.get('my_image_field'), // The filename
  ),
);

// Or get the file bytes directly
final bytes = await client.files.getFileBytes(
  recordId: postRecord.id, 
  recordCollectionName: postRecord.collectionName, 
  fileName: postRecord.get('my_image_field'),
  requestPolicy: RequestPolicy.cacheAndNetwork,
);
```

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
} catch (e) {
  // Handle errors, e.g., if networkOnly fails or cache is empty
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

// Or disable automatic cleanup (keep data forever)
final clientNoExpiry = $PocketBase.database(
  'https://example.pocketbase.io',
  cacheTtl: null,
);
```

#### Running Maintenance

Call `runMaintenance()` to clean up expired cached data. This is typically done on app startup or periodically:

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
- `deletedFiles` - Number of expired file blobs deleted
- `totalDeleted` - Total items cleaned up

**Important**: Maintenance only deletes **synced** data. Unsynced local changes, local-only records (`noSync: true`), and pending deletions are **never** removed, ensuring you never lose data that hasn't been synced to the server.

## Authentication Persistence

The library provides a specialized `$AuthStore` that integrates with `shared_preferences` to persist authentication state across app sessions.

By default, when a user logs out (or the auth store is cleared), all local cached data is deleted for security. You can change this behavior if you want to preserve offline data between sessions:

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

## Advanced: Direct Database Access

For advanced use cases like custom SQL queries, complex joins, or direct table inspection, you can access the underlying Drift database directly via `client.db`.

### Database Schema

All PocketBase records are stored in a generic `services` table with the following structure:

| Column | Type | Description |
|--------|------|-------------|
| `id` | TEXT | Record ID (PocketBase ID) |
| `service` | TEXT | Collection name (e.g., "posts", "users") |
| `data` | TEXT | JSON-encoded record data |
| `created` | TEXT | ISO 8601 timestamp |
| `updated` | TEXT | ISO 8601 timestamp |

**Primary Key**: `(id, service)`

Additional tables:
- `blob_files` - Cached file/image blobs
- `cached_responses` - Cached API responses for custom routes

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

### Executing Raw Statements

For INSERT, UPDATE, DELETE operations, use `customStatement`:

```dart
await client.db.customStatement(
  "DELETE FROM services WHERE service = 'temp_data'",
);
```

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

## TODO


-   [X] Offline mutations and retry
-   [X] Offline collections & records
-   [X] Full-text search
-   [X] Support for fields (select), sort, expand, and pagination
-   [X] Robust file caching and streaming for large files
-   [X] Proactive connectivity handling
-   [X] Structured logging
-   [X] Add support for indirect expand (e.g., `post.author.avatar`)
-   [X] Add support for more complex query operators (e.g., ~ for LIKE/Contains)
-   [X] More comprehensive test suite for edge cases
-   [X] Cache TTL & maintenance for expired data cleanup
-   [X] Batch requests with offline support

## Credits
 
- [Rody Davis](https://github.com/rodydavis) (Original Creator)
