# CRUD Operations

This guide covers create, read, update, and delete operations with offline support.

## Reading Records

### Get a Single Record

```dart
// By ID
final post = await client.collection('posts').getOne(
  'RECORD_ID',
  expand: 'author',
  requestPolicy: RequestPolicy.cacheAndNetwork,
);

// Access fields
final title = post.get<String>('title');
final created = DateTime.parse(post.get('created'));
```

### Get One or Null

Returns `null` instead of throwing if the record does not exist (404 from the server, or not cached while the server is unreachable). Other errors are thrown:

```dart
final post = await client.collection('posts').getOneOrNull(
  'RECORD_ID',
  requestPolicy: RequestPolicy.cacheAndNetwork,
);

if (post != null) {
  // Use post
}
```

### Get List with Pagination

```dart
final result = await client.collection('posts').getList(
  page: 1,
  perPage: 20,
  filter: "published = true",
  sort: '-created',
  expand: 'author',
  requestPolicy: RequestPolicy.cacheAndNetwork,
);

// Access pagination info
print('Page ${result.page} of ${result.totalPages}');
print('Total items: ${result.totalItems}');

// Access items
for (final post in result.items) {
  print(post.get<String>('title'));
}
```

### Get Full List

Fetches all records (automatically handles pagination):

```dart
final posts = await client.collection('posts').getFullList(
  filter: "author = '${userId}'",
  sort: '-created',
  expand: 'author,tags',
  requestPolicy: RequestPolicy.cacheAndNetwork,
);
```

### Get First List Item

```dart
final latestPost = await client.collection('posts').getFirstListItem(
  "published = true",
  sort: '-created',
  requestPolicy: RequestPolicy.cacheAndNetwork,
);

// Or get null if not found
final post = await client.collection('posts').getFirstListItemOrNull(
  "slug = '${slug}'",
);
```

## Creating Records

### Basic Create

```dart
final newPost = await client.collection('posts').create(
  body: {
    'title': 'My New Post',
    'content': 'This is the content.',
    'published': false,
    'author': userId,
  },
  requestPolicy: RequestPolicy.cacheAndNetwork,
);

print('Created post with ID: ${newPost.id}');
```

With `cacheAndNetwork`:
- The server answers: the record is created on the server and cached.
- The server is unreachable: the record is stored locally as pending and returned. The sync engine creates it on the server later with the same id.
- The server rejects the record (400 validation, 403 rule): `ClientException` is thrown. Nothing is stored.

```dart
try {
  await client.collection('posts').create(body: {'title': ''});
} on ClientException catch (e) {
  if (e.statusCode == 400) {
    final fieldErrors = e.response['data']; // Per-field validation errors
  }
}
```

### Create with Custom ID

```dart
import 'package:pocketbase_drift/pocketbase_drift.dart';

// Generate a PocketBase-compatible ID
final customId = newId();

final post = await client.collection('posts').create(
  body: {
    'id': customId, // Use custom ID
    'title': 'Post with Custom ID',
  },
  requestPolicy: RequestPolicy.cacheAndNetwork,
);
```

### Create with Files

```dart
import 'package:http/http.dart' as http;

// From bytes
final imageBytes = await loadImageBytes();
final file = http.MultipartFile.fromBytes(
  'image', // field name
  imageBytes,
  filename: 'photo.jpg',
);

final post = await client.collection('posts').create(
  body: {'title': 'Post with Image'},
  files: [file],
  requestPolicy: RequestPolicy.cacheAndNetwork,
);
```

When the server is unreachable, the file bytes are stored locally. Sync sends them once as multipart parts. Later edits of the record do not upload them again.

## Updating Records

### Basic Update

```dart
final updatedPost = await client.collection('posts').update(
  'RECORD_ID',
  body: {
    'title': 'Updated Title',
    'published': true,
  },
  requestPolicy: RequestPolicy.cacheAndNetwork,
);
```

### Partial Update

Only the specified fields are updated. An offline update records the changed fields in `pendingFields`. Sync sends only these fields. A field changed only with `+`/`-` modifiers is sent as a modifier (the total change since the server value), so concurrent changes of other devices stay. A plain set (`'view_count': 5`) is last-write-wins. Use modifiers for counters:

```dart
await client.collection('posts').update(
  postId,
  body: {'view_count+': 1}, // Increment operator; merges with other devices
  requestPolicy: RequestPolicy.cacheAndNetwork,
);
```

See `sync.md` ("Conflict Handling") for the rules.

### Update with Files

```dart
await client.collection('posts').update(
  postId,
  body: {'title': 'New Title'},
  files: [newImageFile],
  requestPolicy: RequestPolicy.cacheAndNetwork,
);
```

## Deleting Records

### Basic Delete

```dart
await client.collection('posts').delete(
  'RECORD_ID',
  requestPolicy: RequestPolicy.cacheAndNetwork,
);
```

### Offline Delete Behavior

When using `cacheAndNetwork`:
- Server answers: Deletes from server, then removes from cache. A 404 also removes the local copy without an error.
- Server unreachable: Marks record as `deleted: true` in cache, syncs deletion when the server is reachable again
- Record not cached and server unreachable: the deletion is queued as a bare tombstone (id and bookkeeping keys only)
- Record created offline and not synced yet: Removed locally at once. No server delete is queued.
- Server rejects the delete (for example 403): `ClientException` is thrown. The cached record stays.

With `cacheFirst`, the deletion is queued locally first (also for a record that is not cached) and pushed in the background when the server is reachable. A record created offline and not synced yet is removed locally at once. A 404 at sync time (already deleted, or the delete rule does not match) ends the queued deletion without a `SyncFailure`.

## Filtering

PocketBase filter syntax works locally. Supported right-hand sides: literals (strings, numbers, `true`/`false`, `null`), date macros (`@now`, `@todayStart`, `@yesterday`, ...) and `@request.auth.id` (the logged-in account id, or `''` when nobody is logged in). Other `@request.*` values, `@collection.*` and field references on the right-hand side throw `UnsupportedError` in local queries. Malformed filters throw `FormatException`. Server requests are not affected.

```dart
// Equality
final posts = await client.collection('posts').getFullList(
  filter: "status = 'published'",
);

// Comparison
final recentPosts = await client.collection('posts').getFullList(
  filter: "created >= '2024-01-01'",
);

// Boolean AND
final myPublished = await client.collection('posts').getFullList(
  filter: "author = '${userId}' && published = true",
);

// Boolean OR
final hotOrNew = await client.collection('posts').getFullList(
  filter: "featured = true || created >= '2024-01-01'",
);

// Contains (LIKE)
final search = await client.collection('posts').getFullList(
  filter: "title ~ '%flutter%'",
);

// NOT
final unpublished = await client.collection('posts').getFullList(
  filter: "published != true",
);

// NULL check
final withImage = await client.collection('posts').getFullList(
  filter: "image != ''",
);
```

## Sorting

```dart
// Ascending
final posts = await client.collection('posts').getFullList(
  sort: 'title',
);

// Descending (prefix with -)
final posts = await client.collection('posts').getFullList(
  sort: '-created',
);

// Multiple fields
final posts = await client.collection('posts').getFullList(
  sort: '-featured,created',
);
```

## Field Selection

Limit returned fields for performance:

```dart
final posts = await client.collection('posts').getFullList(
  fields: 'id,title,created',
);
```

## Error Handling

```dart
try {
  final post = await client.collection('posts').getOne(postId);
  // Use post
} on ClientException catch (e) {
  if (e.statusCode == 0) {
    // Server unreachable and the record is not cached
  } else if (e.statusCode == 404) {
    // Not found on the server. The stale cached copy is removed
    // (unless it has unsynced local changes).
  } else {
    // Other server answer (400, 401, 403) or transient status (for example 503)
  }
}
```

Reads use the cache only when the server is unreachable (status 0, timeout, 408, 429, 5xx). A 4xx answer is always thrown. A pending offline create is still returned from the cache when the server answers 404. A local filter (list reads, streams) with an unsupported right-hand side throws `UnsupportedError`. A malformed filter throws `FormatException`.

## Checking Sync Status

Records have metadata indicating sync state:

```dart
// Read the cached row: server responses do not contain the sync metadata
final post = await client.collection('posts').getOne(
  postId,
  requestPolicy: RequestPolicy.cacheOnly,
);

final synced = !RecordMeta.isPending(post.data);
final isNew = RecordMeta.flag(post.data[RecordMeta.isNew]);
final noSync = RecordMeta.flag(post.data[RecordMeta.noSync]);

if (!synced && isNew) {
  print('Created offline, pending sync');
}
if (!synced && !isNew) {
  print('Updated offline, pending sync');
}
if (noSync) {
  print('Local-only record, will never sync');
}
```

> **Note:** Offline-deleted records are stored as local tombstones and are hidden from all
> reads (`getOne`, `getFullList`, `watchRecords`, `search`, `$count`). To inspect them
> (diagnostics, pending-queue screens), query the database directly with
> `client.db.$query(collection, includeDeleted: true)`. A record created offline and
> deleted before it syncs is removed locally at once — it never hits the server.
