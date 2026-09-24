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

Returns `null` instead of throwing if not found:

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

Only the specified fields are updated:

```dart
await client.collection('posts').update(
  postId,
  body: {'view_count+': 1}, // Increment operator
  requestPolicy: RequestPolicy.cacheAndNetwork,
);
```

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
- If online: Deletes from server, then removes from cache
- If offline: Marks record as `deleted: true` in cache, syncs deletion when online

## Filtering

PocketBase filter syntax works locally:

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
  if (e.statusCode == 404) {
    // Record not found
  } else {
    // Other error
  }
} catch (e) {
  // Network or cache error
}
```

## Checking Sync Status

Records have metadata indicating sync state:

```dart
final post = await client.collection('posts').getOne(postId);

final synced = post.data['synced'] as bool? ?? true;
final isNew = post.data['isNew'] as bool? ?? false;
final deleted = post.data['deleted'] as bool? ?? false;
final noSync = post.data['noSync'] as bool? ?? false;

if (!synced && isNew) {
  print('Created offline, pending sync');
}
if (!synced && !isNew) {
  print('Updated offline, pending sync');
}
if (deleted) {
  print('Marked for deletion, pending sync');
}
if (noSync) {
  print('Local-only record, will never sync');
}
```

> **Note:** Offline-deleted records are stored as local tombstones and are hidden from all
> reads (`getOne`, `getFullList`, `watchRecords`, `search`, `$count`). To inspect them
> (diagnostics, pending-queue screens), query the database directly with
> `client.db.$query(collection, includeDeleted: true)`. A record created offline and
> deleted before ever syncing is purged locally during sync — it never hits the server.
