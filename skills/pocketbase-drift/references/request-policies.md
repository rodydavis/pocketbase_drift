# Request Policies

This guide covers the 5 RequestPolicy options and when to use each.

## Overview

`RequestPolicy` controls how data flows between local cache and remote server:

```dart
enum RequestPolicy {
  cacheAndNetwork, // Default - balanced offline-first
  cacheFirst,      // Optimistic - instant UI
  cacheOnly,       // Local only - never syncs
  networkFirst,    // Fresh data - strict consistency
  networkOnly,     // Server only - no caching
}
```

## When the Cache Replaces the Server

The cache never hides a server answer. A policy that can use the cache does so only when the server is **unreachable**:

- `ClientException` with status 0 (no connection, socket error).
- Request timeout (`requestTimeout`, see below).
- Status 408, 429 or 5xx (including 502, 503, 504).

Every other answer (400, 401, 403, 404) is the server's final answer. The package throws it as `ClientException` with the server status. Writes rejected this way store nothing in the cache.

## For Read Operations (GET)

### cacheAndNetwork (Default)

**Balanced offline-first behavior.**

- For one-time fetches: Tries the server first. Falls back to the cache only when the server is unreachable. Same as `networkFirst`.
- For streams (`watchRecords`): Emits cache immediately, then updates with server data and follows realtime events

```dart
// Default behavior
final posts = await client.collection('posts').getFullList();

// Explicit
final posts = await client.collection('posts').getFullList(
  requestPolicy: RequestPolicy.cacheAndNetwork,
);
```

**Use when:** General-purpose offline-first apps.

### cacheFirst

**Prioritizes instant UI response.**

- Returns cached data immediately
- Fetches from the server in the background (when the server is reachable) to update the cache for next time
- If nothing is cached, waits for the server like `networkFirst`

```dart
final posts = await client.collection('posts').getFullList(
  requestPolicy: RequestPolicy.cacheFirst,
);
```

**Use when:** UI responsiveness is critical and slightly stale data is acceptable.

### cacheOnly

**Only reads from local cache, never contacts server.**

- `getOne` of a record that is not cached throws `CacheMissException`

```dart
final posts = await client.collection('posts').getFullList(
  requestPolicy: RequestPolicy.cacheOnly,
);
```

**Use when:** Working exclusively with locally available data.

### networkFirst

**Prioritizes fresh data from server.**

- Tries to fetch from remote server first
- On success, updates cache and returns fresh data
- When the server is unreachable, falls back to cached data
- A 4xx answer is thrown. A 404 from `getOne` also removes the stale cached copy (unless it has unsynced local changes)
- When the server is unreachable and nothing is cached, throws `ClientException` with status 0

```dart
final posts = await client.collection('posts').getFullList(
  requestPolicy: RequestPolicy.networkFirst,
);
```

**Use when:** Need freshest data possible, but can accept stale data when the server is unreachable.

### networkOnly

**Only reads from server, never uses cache.**

- Throws `ClientException` if the server is unreachable (status 0 when there is no network interface or the request times out)
- Streams (`watchRecords`, `watchRecord`) with `networkOnly` emit the server's data and refetch on realtime events. They do not read the cache.

```dart
final posts = await client.collection('posts').getFullList(
  requestPolicy: RequestPolicy.networkOnly,
);
```

**Use when:** Absolutely need fresh data and can't accept stale data.

---

## For Write Operations (CREATE/UPDATE/DELETE)

### cacheAndNetwork (Default)

**Resilient offline-first.**

- Tries to write to server first
- On success, updates local cache
- When the server is unreachable (or known to be down), writes to the cache and marks the record as pending. The sync engine sends it later.
- When the server rejects the write (for example 400 validation, 403 rule), throws `ClientException`. Nothing is stored in the cache.

```dart
await client.collection('posts').create(
  body: {'title': 'My Post'},
  requestPolicy: RequestPolicy.cacheAndNetwork,
);
```

**Use when:** General-purpose offline-first apps that need to work offline.

### cacheFirst

**Optimistic updates with background sync.**

- Writes to cache first (as pending), returns success immediately
- Pushes the change to the server in the background when the server is reachable
- A server rejection is not thrown to the caller. It counts towards `localSyncRetryCount`. At the limit, the change is parked and reported on `client.syncFailures` (see `sync.md`).

```dart
await client.collection('posts').create(
  body: {'title': 'My Post'},
  requestPolicy: RequestPolicy.cacheFirst,
);
```

**Use when:** Instant UI feedback is critical (note-taking, drafts).

### cacheOnly

**Local-only, never syncs.**

- Writes to cache only
- Records marked as `noSync: true` - will NEVER sync to server

```dart
await client.collection('user_preferences').create(
  body: {'theme': 'dark'},
  requestPolicy: RequestPolicy.cacheOnly,
);
```

**Use when:** Local-only data (user preferences, temp data, offline-only features).

### networkFirst

**Server is source of truth (strict consistency).**

- Writes to server first
- On success, updates local cache
- On failure, **throws error** (no cache fallback). Status 0 means the server is unreachable.
- An update that gets 404 or 400 is not turned into a create. It throws. A 404 also removes the cached copy (unless it has unsynced local changes).

```dart
await client.collection('orders').create(
  body: {'product_id': '123', 'quantity': 1},
  requestPolicy: RequestPolicy.networkFirst,
);
```

**Use when:** Data integrity is critical (financial transactions, inventory).

### networkOnly

**Server only, never touches cache.**

- Writes directly to server
- Throws `ClientException` if the server is unreachable or rejects the write

```dart
await client.collection('analytics').create(
  body: {'event': 'page_view'},
  requestPolicy: RequestPolicy.networkOnly,
);
```

**Use when:** Need immediate server confirmation, no local state needed.

---

## Choosing the Right Policy

| Scenario | Read Policy | Write Policy |
|----------|-------------|--------------|
| **Real-time collaborative app** | `networkFirst` | `networkFirst` |
| **Offline-first mobile app** | `cacheAndNetwork` | `cacheAndNetwork` |
| **Instant feedback UI** (notes, drafts) | `cacheFirst` | `cacheFirst` |
| **Financial transactions** | `networkOnly` | `networkFirst` |
| **Analytics/telemetry** | N/A | `networkOnly` |
| **Local-only settings** | `cacheOnly` | `cacheOnly` |
| **News feed** (freshness matters) | `networkFirst` | N/A |
| **Offline form submission** | N/A | `cacheAndNetwork` |

---

## Behavior Summary

### Read Policies

| Policy | Server answers | Server unreachable | Server rejects (4xx) |
|--------|----------------|--------------------|----------------------|
| `cacheAndNetwork` | Network → Cache update | Cache fallback; not cached → `ClientException` status 0 | **Throws** server status |
| `cacheFirst` | Cache → Background refresh; not cached → waits for server | Cache only; not cached → `ClientException` status 0 | Cached → cache returned; not cached → **throws** |
| `cacheOnly` | Cache only | Cache only | Not contacted |
| `networkFirst` | Network → Cache update | Cache fallback; not cached → `ClientException` status 0 | **Throws** server status |
| `networkOnly` | Network only | **Throws** `ClientException` | **Throws** server status |

### Write Policies

| Policy | Server answers | Server unreachable | Server rejects (4xx) |
|--------|----------------|--------------------|----------------------|
| `cacheAndNetwork` | Network → Cache | Cache + pending sync | **Throws**, nothing stored |
| `cacheFirst` | Cache → Background sync | Cache + pending sync | Not thrown; retried, then parked (`syncFailures`) |
| `cacheOnly` | Cache only (noSync) | Cache only (noSync) | Not contacted |
| `networkFirst` | Network → Cache | **Throws** | **Throws** server status |
| `networkOnly` | Network only | **Throws** | **Throws** server status |

"Server unreachable" means status 0, timeout, socket error, 408, 429 or 5xx.

---

## Request Timeout

`requestTimeout` limits single-record reads (`getOne`) and writes without file uploads. The default is 15 seconds. When the limit elapses, offline-first writes are queued and reads fall back to the cache. Set it to `null` to disable it. List reads (`getList`, `getFullList`) use their own `timeout` argument.

```dart
final client = $PocketBase.database(
  'https://your-pb.example.com',
  requestTimeout: const Duration(seconds: 10),
);
```

---

## Error Handling

Catch `ClientException`. Use `statusCode` to tell an unreachable server from a server answer.

```dart
try {
  await client.collection('posts').create(
    body: {'title': 'My Post'},
    requestPolicy: RequestPolicy.networkFirst,
  );
} on ClientException catch (e) {
  if (e.statusCode == 0) {
    // The server did not answer: no connection, socket error, or
    // requestTimeout elapsed (e.originalError holds the cause).
    // With cacheAndNetwork, this write would be queued instead of thrown.
  } else if (e.statusCode >= 500) {
    // The server is down or busy (502/503/504 keep the server's status).
    // Try again later.
  } else if (e.statusCode == 400) {
    // Validation failed. Show e.response['data'] next to the form fields.
  } else if (e.statusCode == 403) {
    // An API rule rejected the write.
  }
}
```

A read throws `ClientException` with status 0 when the server is unreachable and the record is not cached. A transient server status (for example 503) can also reach the caller in that case. `networkFirst` and `networkOnly` writes convert connectivity failures (no connection, socket error, `requestTimeout` elapsed) to `ClientException` with status 0; `originalError` holds the cause. A 502, 503 or 504 answer stays the server's `ClientException`.

---

## Example: Mixed Policies in App

```dart
class PostRepository {
  PostRepository(this._client);
  final $PocketBase _client;

  // Posts should be fresh but work offline
  Future<List<RecordModel>> getPosts() => _client.collection('posts').getFullList(
    requestPolicy: RequestPolicy.cacheAndNetwork,
  );

  // Creating posts works offline, syncs later
  Future<RecordModel> createPost(Map<String, dynamic> data) => 
    _client.collection('posts').create(
      body: data,
      requestPolicy: RequestPolicy.cacheAndNetwork,
    );

  // User preferences are local-only
  Future<RecordModel> savePreferences(Map<String, dynamic> prefs) =>
    _client.collection('user_preferences').create(
      body: prefs,
      requestPolicy: RequestPolicy.cacheOnly,
    );

  // Orders require server confirmation
  Future<RecordModel> createOrder(Map<String, dynamic> order) =>
    _client.collection('orders').create(
      body: order,
      requestPolicy: RequestPolicy.networkFirst,
    );
}
```
