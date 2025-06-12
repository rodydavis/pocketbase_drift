A powerful, offline-first Flutter client for [PocketBase](https://pocketbase.io), backed by the reactive persistence of [Drift](https://drift.simonbinder.eu) (the Flutter & Dart flavor of `moor`).

This library extends the official PocketBase Dart SDK to provide a seamless offline-first experience. It automatically caches data from your PocketBase instance into a local SQLite database, allowing your app to remain fully functional even without a network connection. Changes made while offline are queued and automatically retried when connectivity is restored.

## Features

*   **Offline-First Architecture**: Read, create, update, and delete records even without a network connection. The client seamlessly uses the local database as the source of truth.
*   **Automatic Synchronization**: Changes made while offline are automatically queued and retried when network connectivity is restored.
*   **Reactive Data & UI**: Build reactive user interfaces with streams that automatically update when underlying data changes, whether from a server push or a local mutation.
*   **Local Caching with Drift**: All collections and records are cached in a local SQLite database, providing fast, offline access to your data.
*   **Powerful Local Querying**: Full support for local querying, mirroring the PocketBase API. This includes:
    *   **Filtering**: Complex `filter` strings are parsed into SQLite `WHERE` clauses.
    *   **Sorting**: Sort results by any field with `sort` (e.g., `-created,name`).
    *   **Field Selection**: Limit the returned fields with `fields` for improved performance.
    *   **Pagination**: `limit` and `offset` are fully supported for local data.
*   **Relation Expansion**: Support for expanding single and multi-level relations (e.g., `post.author`) directly from the local cache.
*   **Full-Text Search**: Integrated Full-Text Search (FTS5) for performing fast, local searches across all your cached record data.
*   **Authentication Persistence**: User and admin authentication state is persisted locally using `shared_preferences`, keeping users logged in across app sessions.
*   **Cross-Platform Support**: Works across all Flutter-supported platforms, including mobile (iOS, Android), web, and desktop (macOS, Windows, Linux).
*   **Basic File & Image Caching**: Includes a `PocketBaseImageProvider` that caches images in the local database for offline display.
-   **Robust & Performant**: Includes optimizations for batching queries and handling large files with streams.

## Getting Started

### 1. Add Dependencies

Add the following packages to your `pubspec.yaml`:

```yaml
dependencies:
  pocketbase_drift: ^0.1.0 # Use the latest version
```

### 2. Initialize the Client

Replace a standard `PocketBase` client with a `$PocketBase.database` client. It's that simple.

```diff
- import 'package:pocketbase/pocketbase.dart';
+ import 'package:pocketbase_drift/pocketbase_drift.dart';

- final client = PocketBase('http://127.0.0.1:8090');
+ final client = $PocketBase.database('http://127.0.0.1:8090');
```

### 3. Web Setup

For web, you need to follow the instructions for [Drift on the Web](https://drift.simonbinder.eu/web/#drift-wasm) to copy the `sqlite3.wasm` binary and `drift_worker.js` file into your `web/` directory.

1.  Download the latest `sqlite3.wasm` from the [sqlite3.dart releases](https://github.com/simolus3/sqlite3.dart/releases) and the latest `drift_worker.js` from the [drift releases](https://github.com/simolus3/drift/releases).
2.  Place the each file inside your project's `web/` folder.
3.  Rename `drift_worker.js` to `drift_worker.dart.js`.

## Core Concepts

### RequestPolicy

The `RequestPolicy` enum is central to this library and controls how requests are handled.

-   `RequestPolicy.cacheAndNetwork` (Default): Provides a seamless online/offline experience.
    - For one-time fetches (e.g., getFullList):
      - Tries to fetch fresh data from the remote PocketBase server.
      - If successful, it updates the local cache with the new data and returns it.
      - If the network fails (or the device is offline), it seamlessly falls back to returning data from the local cache without throwing an error.
    - For reactive streams (e.g., watchRecords):
      - The stream immediately emits the data currently in the local cache, making the UI feel instant.
      - A network request is then triggered in the background.
      - If the network data is different, the local cache is updated, and the stream automatically emits the new, fresh data.

-   `RequestPolicy.cacheOnly`:
    -   Only ever reads data from the local cache.
    -   Never makes a network request. Useful for offline-first UI and speed.

-   `RequestPolicy.networkOnly`:
    -   Only ever reads data from the remote server.
    -   Never uses the local cache for reading (but still updates it on success).
    -   Will throw an exception if the network is unavailable.

### Offline Support

When you use `create`, `update`, or `delete` methods, the library automatically handles the network state:

-   **Online**: The operation is sent to the server. If it succeeds, the local cache is updated.
-   **Offline**: The operation is immediately applied to the local cache and marked as "pending sync." The UI will react instantly to the local change. When connectivity is restored, the library will automatically attempt to send the pending change to the server.

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

// Get a single record
final post = await client.collection('posts').getOne('RECORD_ID');
```

### Creating and Updating Records

```dart
// Create a new record (works online and offline)
final newRecord = await client.collection('posts').create(body: {
  'title': 'My Offline Post',
  'content': 'This was created without a connection.',
});

// Update a record
await client.collection('posts').update(newRecord.id, body: {
  'content': 'The content has been updated.',
});
```

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
    record: postRecord, // The RecordModel containing the file
    filename: postRecord.get('my_image_field'), // The filename
  ),
);

// Or get the file bytes directly
final bytes = await client.files.get(postRecord, 'my_image_field.jpg');
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
```
