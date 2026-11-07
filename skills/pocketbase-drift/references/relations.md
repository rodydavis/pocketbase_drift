# Relations

This guide covers expanding and working with related records.

## Overview

PocketBase Drift fully supports relation expansion from the local cache, with full compatibility with the PocketBase SDK's `record.get<T>()` dot-notation syntax.

## Single Relations (maxSelect = 1)

Single relations are returned as objects directly (not wrapped in a list):

```dart
// Fetch a post with its author expanded
final post = await client.collection('posts').getOne(
  'RECORD_ID',
  expand: 'author',
);

// Access expanded data directly (no index needed)
final authorName = post.get<String>('expand.author.name');
final authorEmail = post.get<String>('expand.author.email', 'No email'); // With default

// Get the expanded record as a RecordModel
final author = post.get<RecordModel>('expand.author');
print(author?.get<String>('name'));
```

## Multi Relations (maxSelect > 1)

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
final tags = post.get<List<RecordModel>>('expand.tags') ?? [];
for (final tag in tags) {
  print(tag.get<String>('name'));
}
```

## Nested (Multi-Level) Expansion

Expand multiple levels of relations:

```dart
// post -> author -> profile (all single relations)
final post = await client.collection('posts').getOne(
  'RECORD_ID',
  expand: 'author.profile',
);

// Access deeply nested fields
final bio = post.get<String>('expand.author.expand.profile.bio');
final avatar = post.get<String>('expand.author.expand.profile.avatar');
```

## Multiple Expansions

Expand multiple relations at once:

```dart
final post = await client.collection('posts').getOne(
  'RECORD_ID',
  expand: 'author,tags,category',
);

final authorName = post.get<String>('expand.author.name');
final categoryName = post.get<String>('expand.category.name');
final tags = post.get<List<RecordModel>>('expand.tags') ?? [];
```

## Expansion in Lists

```dart
final posts = await client.collection('posts').getFullList(
  expand: 'author',
  sort: '-created',
);

for (final post in posts) {
  final title = post.get<String>('title');
  final authorName = post.get<String>('expand.author.name');
  print('$title by $authorName');
}
```

## Expansion in Streams

```dart
final postsProvider = StreamProvider<List<RecordModel>>((ref) {
  final client = ref.watch(pocketbaseProvider);
  return client.collection('posts').watchRecords(
    expand: 'author,category',
    sort: '-created',
  );
});

// In widget
final posts = ref.watch(postsProvider).valueOrNull ?? [];
for (final post in posts) {
  final author = post.get<RecordModel>('expand.author');
  // ...
}
```

## How Expansion Works with Cache

When you expand relations, pocketbase_drift:

1. **On Network Fetch**: Fetches expanded records from server and caches them to their respective collection tables
2. **On Cache Read**: Performs local joins to reconstruct expansions
3. **Automatic Caching**: Expanded records are independently queryable after caching

```dart
// This caches the author record to the 'users' collection
final post = await client.collection('posts').getOne(
  'POST_ID',
  expand: 'author',
);

// Now you can fetch the author directly
final author = await client.collection('users').getOne(
  post.get<String>('author')!, // The author ID
  requestPolicy: RequestPolicy.cacheOnly, // Works from cache!
);
```

## Accessing Relation IDs

Get the raw relation IDs (not expanded):

```dart
// Single relation - returns string
final authorId = post.get<String>('author');

// Multi relation - returns list of strings
final tagIds = post.get<List<String>>('tags') ?? [];
```

## Checking if Relation is Expanded

```dart
final expand = post.data['expand'] as Map<String, dynamic>?;

if (expand != null && expand.containsKey('author')) {
  // Author is expanded
  final author = post.get<RecordModel>('expand.author');
} else {
  // Author is not expanded, only have ID
  final authorId = post.get<String>('author');
}
```

## Best Practices

### Expand Only What You Need

```dart
// ✅ GOOD: Expand only needed relations
final posts = await client.collection('posts').getFullList(
  expand: 'author', // Only author needed for list view
);

// ❌ BAD: Over-fetching
final posts = await client.collection('posts').getFullList(
  expand: 'author,author.profile,tags,category,comments',
);
```

### Use Separate Queries for Deep Nesting

```dart
// For complex views, fetch in stages
final post = await client.collection('posts').getOne(postId, expand: 'author');
final authorProfile = await client.collection('profiles').getFirstListItem(
  "user = '${post.get<String>('author')}'",
);
```

### Handle Missing Expansions

```dart
// Always use null-safe access
final authorName = post.get<String>('expand.author.name') ?? 'Unknown Author';

// Or check first
final author = post.get<RecordModel>('expand.author');
if (author != null) {
  // Use author
} else {
  // Handle missing expansion
}
```

## Example: Blog Post with Relations

```dart
// Schema:
// posts: title, content, author (-> users), tags (-> tags), category (-> categories)

// Fetch with all relations
final post = await client.collection('posts').getOne(
  postId,
  expand: 'author,tags,category',
);

// Display
final title = post.get<String>('title')!;
final content = post.get<String>('content')!;
final authorName = post.get<String>('expand.author.name') ?? 'Anonymous';
final authorAvatar = post.get<String>('expand.author.avatar');
final categoryName = post.get<String>('expand.category.name') ?? 'Uncategorized';
final tags = post.get<List<RecordModel>>('expand.tags') ?? [];

print('$title by $authorName in $categoryName');
print('Tags: ${tags.map((t) => t.get<String>('name')).join(', ')}');
```
