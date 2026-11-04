# Direct SQL

This guide covers accessing the Drift database directly for custom queries.

## Database Access

Access the underlying Drift database via `client.db`:

```dart
final db = client.db;
```

On native platforms, the default connection runs SQLite in a background isolate (`NativeDatabase.createInBackground`, WAL mode). Queries do not block the UI isolate. A client with `inMemory: true` runs SQLite on the calling isolate.

## Database Schema

All PocketBase records are stored in a generic `services` table:

| Column | Type | Description |
|--------|------|-------------|
| `id` | TEXT | Record ID (PocketBase ID) |
| `service` | TEXT | Collection name (e.g., "posts", "users"); `schema` holds the collection definitions |
| `data` | TEXT | JSON-encoded record data, including the bookkeeping keys (see below) |
| `created` | TEXT | PocketBase timestamp, e.g. `2026-11-04 10:00:00.123Z` |
| `updated` | TEXT | PocketBase timestamp, e.g. `2026-11-04 10:00:00.123Z` |
| `cachedAt` | INTEGER (nullable) | When the row was last written from the server or by a local change (Drift `DateTime`, Unix seconds). Cache TTL uses this column. |

**Primary Key**: `(id, service)`

**Indexes**: `idx_services_service` on `service`; `idx_blob_files_record` on `BlobFiles (recordId, filename)`

Additional tables:
- `BlobFiles` - Cached file/image blobs (`recordId`, `filename`, `data`, `expiration`, `created`, `updated`). Thumbs are stored under `filename?thumb=<spec>`.
- `CachedResponses` - Cached API responses for custom routes (`requestKey`, `responseData`, `cachedAt`)
- `text_entries` - FTS5 index of `services.data`

## Bookkeeping Keys (RecordMeta)

The package stores local state inside the `data` JSON. `RecordMeta` holds the key names:

| Key | Meaning |
|-----|---------|
| `synced` | `false` while a local change is pending. A missing key means synced. |
| `isNew` | Created locally, not on the server yet |
| `deleted` | Tombstone: deleted locally, deletion not synced yet |
| `noSync` | Local-only row (`cacheOnly` write), never synced |
| `retryCount` | Sync attempts the server rejected |
| `pendingFields` | Fields changed by pending updates; sync sends only these |
| `pendingFiles` | Files attached by pending writes |
| `pendingOwner` | Auth record id of the account that made the pending change |
| `pendingRev` | Increments with every local change |
| `syncError` | Set when the change is parked: `status`, `message`, `data`, `at` |

Helpers: `RecordMeta.keys`, `RecordMeta.systemKeys`, `RecordMeta.flag(value)` (JSON booleans can be `0`/`1`), `RecordMeta.isPending(data)`, `RecordMeta.strip(data)` (removes the bookkeeping keys). `pbTimestamp([time])` formats a `DateTime` as a PocketBase timestamp.

```dart
final row = await client.db.customSelect(
  "SELECT data FROM services WHERE service = 'posts' AND id = ?",
  variables: [Variable(postId)],
).getSingleOrNull();

if (row != null) {
  final data = jsonDecode(row.read<String>('data')) as Map<String, dynamic>;
  print('Pending: ${RecordMeta.isPending(data)}');
  print('Server fields: ${RecordMeta.strip(data)}');
}
```

## Pending Changes

Use `pendingRecords` instead of raw SQL to read the sync queue:

```dart
// All collections, oldest first
final pending = await client.db.pendingRecords().get();

// One collection, live
client.db.pendingRecords(service: 'posts').watch().listen((rows) {
  print('${rows.length} unsynced posts');
});
```

`pendingRecords` excludes local-only rows (`noSync`) and rows of other accounts. It includes rows parked with `syncError`. `client.db.pendingServices()` returns the collections with pending rows that the active account can sync now (parked rows excluded).

## Custom Select Queries

### Simple Query

```dart
final results = await client.db.customSelect(
  "SELECT * FROM services WHERE service = 'posts'",
).get();

for (final row in results) {
  final id = row.read<String>('id');
  final dataJson = row.read<String>('data');
  print('Post $id: $dataJson');
}
```

### Query with JSON Extraction

SQLite's `json_extract` function accesses JSON fields:

```dart
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

for (final row in posts) {
  final title = row.read<String>('title');
  final author = row.read<String>('author');
  print('$title by $author');
}
```

## Joining Data Across Collections

Since all collections share the same table, use self-joins:

```dart
final results = await client.db.customSelect('''
  SELECT 
    p.id as post_id,
    json_extract(p.data, '\$.title') as post_title,
    json_extract(u.data, '\$.name') as author_name,
    json_extract(u.data, '\$.email') as author_email
  FROM services p
  JOIN services u 
    ON json_extract(p.data, '\$.author') = u.id 
    AND u.service = 'users'
  WHERE p.service = 'posts'
  ORDER BY p.created DESC
''').get();

for (final row in results) {
  final title = row.read<String>('post_title');
  final author = row.read<String>('author_name');
  print('$title by $author');
}
```

## Reactive Streams

Use `.watch()` instead of `.get()` for reactive updates:

```dart
final stream = client.db.customSelect(
  "SELECT * FROM services WHERE service = 'posts'",
  readsFrom: {client.db.services}, // Required for reactivity
).watch();

stream.listen((rows) {
  print('Posts updated: ${rows.length} items');
});
```

## Execute Statements

For INSERT, UPDATE, DELETE operations. Direct statements do not queue changes for sync and do not set `cachedAt`:

```dart
// Delete all temp data
await client.db.customStatement(
  "DELETE FROM services WHERE service = 'temp_data'",
);

// Update field
await client.db.customStatement('''
  UPDATE services 
  SET data = json_set(data, '\$.viewed', true)
  WHERE service = 'posts' AND id = ?
''', ['POST_ID']);
```

## Built-in Query Builder

For PocketBase-style queries without raw SQL:

```dart
// Uses PocketBase filter syntax internally
final posts = await client.db.$query(
  'posts',
  filter: "published = true && author != ''",
  sort: '-created',
  limit: 10,
).get();

// With expansion
final posts = await client.db.$query(
  'posts',
  filter: "published = true",
  expand: 'author',
  sort: '-created',
).get();
```

Local filters support literals (strings with PocketBase escapes, numbers, `true`, `false`, `null`), date macros (`@now`, `@todayStart`, `@yesterday`, ...) and `@request.auth.id` (the logged-in account id, or `""` when nobody is logged in). Other `@request.*` values, `@collection.*` and field references on the right side throw `UnsupportedError`. `@` tokens on the left side also throw `UnsupportedError`. A malformed filter throws `FormatException`. Server filters are not affected.

`FilterTerm`, `LogicalOperator` and `ValueType` are no longer exported. To translate a filter to SQL yourself, use `FilterParser(filter, baseFields: {...}, now: ..., authId: ...).parse()`.

## Aggregations

```dart
// Count records
final countResult = await client.db.customSelect(
  "SELECT COUNT(*) as count FROM services WHERE service = 'posts'",
).getSingle();
final count = countResult.read<int>('count');

// Sum values
final sumResult = await client.db.customSelect('''
  SELECT SUM(json_extract(data, '\$.price')) as total
  FROM services 
  WHERE service = 'products'
''').getSingle();
final total = sumResult.read<double>('total');

// Group by
final grouped = await client.db.customSelect('''
  SELECT 
    json_extract(data, '\$.category') as category,
    COUNT(*) as count
  FROM services
  WHERE service = 'products'
  GROUP BY json_extract(data, '\$.category')
''').get();
```

## Full-Text Search Table

FTS5 search uses a separate virtual table, `text_entries`:

```dart
// Search using FTS5
final results = await client.db.customSelect('''
  SELECT s.*
  FROM text_entries
  JOIN services s ON s.rowid = text_entries.rowid
  WHERE text_entries MATCH 'flutter'
    AND s.service = 'posts'
''').get();
```

This raw query also returns tombstones and unsynced rows of other accounts. `client.db.search(query, service: 'posts')` excludes them.

## Transactions

```dart
await client.db.transaction(() async {
  await client.db.customStatement(
    "UPDATE services SET data = json_set(data, '\$.status', 'processing') WHERE id = ?",
    [orderId],
  );
  
  await client.db.customStatement(
    "INSERT INTO services (id, service, data) VALUES (?, 'logs', ?)",
    [newId(), '{"action": "order_processed"}'],
  );
});
```

## Inspecting Tables

```dart
// List all services (collections) in cache
final services = await client.db.customSelect(
  "SELECT DISTINCT service FROM services",
).get();

for (final row in services) {
  print('Collection: ${row.read<String>('service')}');
}

// Count records per collection
final counts = await client.db.customSelect('''
  SELECT service, COUNT(*) as count
  FROM services
  GROUP BY service
''').get();
```

## Example: Dashboard Stats

```dart
Future<DashboardStats> getDashboardStats() async {
  final results = await client.db.customSelect('''
    SELECT
      (SELECT COUNT(*) FROM services WHERE service = 'posts') as post_count,
      (SELECT COUNT(*) FROM services WHERE service = 'users') as user_count,
      (SELECT COUNT(*) FROM services WHERE service = 'posts' 
       AND json_extract(data, '\$.published') = 1) as published_count
  ''').getSingle();

  // Pending changes of the active account (local-only rows excluded)
  final pending = await client.db.pendingRecords().get();

  return DashboardStats(
    postCount: results.read<int>('post_count'),
    userCount: results.read<int>('user_count'),
    publishedCount: results.read<int>('published_count'),
    pendingSyncCount: pending.length,
  );
}
```

## Performance Tips

### Use Indexes

The `services` table has the primary key `(id, service)` and the index `idx_services_service` on `service`. JSON fields have no index:

```dart
// This is fast (uses index)
await client.db.$query('posts', filter: "id = 'abc123'").get();

// This is slower (scans table)
await client.db.customSelect('''
  SELECT * FROM services 
  WHERE json_extract(data, '\$.author') = 'user123'
''').get();
```

### Limit Results

```dart
// Always limit when possible
final recent = await client.db.customSelect('''
  SELECT * FROM services 
  WHERE service = 'posts'
  ORDER BY created DESC
  LIMIT 20
''').get();
```

### Use Parameters

```dart
// ✅ Safe from SQL injection
await client.db.customSelect(
  "SELECT * FROM services WHERE service = ? AND id = ?",
  variables: [Variable('posts'), Variable(postId)],
).get();

// ❌ Vulnerable to injection
await client.db.customSelect(
  "SELECT * FROM services WHERE id = '$postId'", // DON'T DO THIS
).get();
```
