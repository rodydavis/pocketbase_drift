# Reactive Streams

This guide covers reactive data streams with watchRecords and watchRecord.

## Overview

Streams emit when the data of their collection changes, from any source:
- Local cache updates
- Network fetches
- Realtime subscriptions (WebSocket)
- Background sync operations

Watch scope:
- Record watchers (`watchRecord(s)`, `watchRecord(s)State`, `client.db.$query(...).watch()`) re-run only for writes to their own collection and to the collections in their `expand`. With `expand`, schema changes re-run them too. A write to another collection does not re-run them.
- Raw SQL writes re-run record watchers only when drift is told: `customUpdate(..., updates: {client.db.services})`, or `client.db.markTablesUpdated({client.db.services})` after `customStatement`. `customStatement` alone notifies no stream.
- `client.db.pendingRecords().watch()`, `search(...).watch()` and app queries with `customSelect(readsFrom: {client.db.services})` re-run on every write to any collection.
- Open streams follow an account switch. After a login with another account, they show the pending changes of the new account and apply `@request.auth.id` filters for it, without a new listen.

## Watch Multiple Records (with QueryState)

Use `watchRecordsState` to receive a `QueryState<List<RecordModel>>` that exposes the data, `isFetchingNetwork` status (to eliminate startup loading flicker), and any `error`:

```dart
// Watch all posts with background fetch status
Stream<QueryState<List<RecordModel>>> stream = client.collection('posts').watchRecordsState();

// Or simple data stream
Stream<List<RecordModel>> stream = client.collection('posts').watchRecords();
// With filtering
Stream<List<RecordModel>> stream = client.collection('posts').watchRecords(
  filter: "author = '${userId}'",
  sort: '-created',
  limit: 20,
  expand: 'author',
  requestPolicy: RequestPolicy.cacheAndNetwork,
);

// Listen to stream
stream.listen((posts) {
  print('Received ${posts.length} posts');
  for (final post in posts) {
    print(post.get<String>('title'));
  }
});
```

`limit` sets how many records the query fetches from the server: the first page of `sort`. Without `limit`, the query fetches the full list.

### QueryState Errors

`QueryState.error` holds the error of the last network fetch. The next successful fetch clears it.

- An unreachable server is not an error for cache-backed queries. They keep the cached data and mark it stale. `cacheAndNetwork` and `networkFirst` queries refresh when the server is reachable again.
- Other fetch errors (for example 403, or a bad filter) set `error` and add an error event to the stream. The stream stays open.
- Local filters with `@request.*` (other than `@request.auth.id`), `@collection.*` or field references on the right side throw `UnsupportedError`. `@` tokens on the left side also throw `UnsupportedError`. A malformed filter throws `FormatException`. The query reports these errors in the same way.

```dart
client.collection('posts').watchRecordsState(limit: 20).listen(
  (state) {
    if (state.hasError) {
      print('Last fetch failed: ${state.error}');
    }
    print('${state.data.length} posts, fetching: ${state.isFetchingNetwork}');
  },
  onError: (Object e) {
    // The same error, also delivered as a stream error event.
  },
);
```

## Watch Single Record

```dart
// Watch specific record
Stream<RecordModel?> stream = client.collection('posts').watchRecord(
  'RECORD_ID',
  expand: 'author,tags',
  requestPolicy: RequestPolicy.cacheAndNetwork,
);

// Listen to changes
stream.listen((post) {
  if (post != null) {
    print('Post updated: ${post.get<String>('title')}');
  } else {
    print('Post was deleted');
  }
});
```

## How watchRecords Works

When `watchRecords` is called with a cache-backed policy:

1. **Initial Cache Emit** - Emits the cached data
2. **Realtime Subscribe** - Joins the realtime subscription of the collection (`cacheAndNetwork`, `networkFirst`)
3. **Network Fetch** - Fetches from the server (only `limit` records if set) when the server is reachable
4. **Cache Update** - Writes the server data to the cache; the stream emits from the cache
5. **Ongoing Updates** - Emits whenever data changes (local or server)
6. **Refetch** - Fetches again after a realtime reconnect and when the server becomes reachable, so changes made while disconnected are not missed

With `networkOnly`, the stream emits the server's data and does not use the cache. It fetches again on every realtime event of the collection.

```
┌─────────────────────────────────────────────────────────┐
│                    watchRecords()                       │
├─────────────────────────────────────────────────────────┤
│ 1. Emit cached data                                     │
│ 2. Subscribe to realtime updates (shared per topic)     │
│ 3. Fetch from network (if policy allows)                │
│ 4. Emit on a change of this collection (or expanded):   │
│    - Local create/update/delete                         │
│    - Network sync                                       │
│    - Realtime event                                     │
│ 5. Refetch after reconnect / server reachable again     │
└─────────────────────────────────────────────────────────┘
```

## Using with Riverpod

### StreamProvider (Recommended)

```dart
// All posts
final postsProvider = StreamProvider<List<RecordModel>>((ref) {
  final client = ref.watch(pocketbaseProvider);
  return client.collection('posts').watchRecords(
    sort: '-created',
    expand: 'author',
  );
});

// Filtered by user
final userPostsProvider = StreamProvider.family<List<RecordModel>, String>((ref, userId) {
  final client = ref.watch(pocketbaseProvider);
  return client.collection('posts').watchRecords(
    filter: "author = '$userId'",
    sort: '-created',
  );
});

// Single post
final postProvider = StreamProvider.family<RecordModel?, String>((ref, postId) {
  final client = ref.watch(pocketbaseProvider);
  return client.collection('posts').watchRecord(
    postId,
    expand: 'author,tags',
  );
});
```

### UI Usage

```dart
class PostListScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final postsAsync = ref.watch(postsProvider);
    
    return postsAsync.when(
      data: (posts) => ListView.builder(
        itemCount: posts.length,
        itemBuilder: (context, index) => PostCard(post: posts[index]),
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => ErrorView(
        message: error.toString(),
        onRetry: () => ref.invalidate(postsProvider),
      ),
    );
  }
}
```

## Realtime Updates

Streams with `cacheAndNetwork`, `networkFirst` and `networkOnly` subscribe to PocketBase realtime events:

```dart
// When another user creates a post, your stream emits with the new post
// When the server updates a post, your stream emits with updated data
// When a post is deleted on server, your stream emits without that post
```

All live queries of a collection share one realtime subscription per topic. Each server event is written to the cache one time. A pending local edit wins over realtime events until it is synced.

### Manual Subscription

For more control over realtime events:

```dart
final unsubscribe = await client.collection('posts').subscribe(
  '*', // '*' for all records, or specific record ID
  (event) {
    print('Action: ${event.action}'); // create, update, delete
    print('Record: ${event.record}');
  },
);

// Later, unsubscribe
await unsubscribe();
```

## Request Policy for Streams

The policy sets where the data comes from and whether the stream gets realtime updates:

| Policy | Behavior | Realtime |
|--------|----------|----------|
| `cacheAndNetwork` | Emit cache, refresh from network, refetch after reconnect | Yes |
| `cacheFirst` | Emit cache, refresh from network one time | No |
| `cacheOnly` | Emit cache only | No |
| `networkFirst` | Emit cache, refresh from network, refetch after reconnect | Yes |
| `networkOnly` | Emit server data only (no cache), refetch on realtime events | Yes |

With `networkOnly`, a failed fetch is a stream error. When the server is unreachable, the error is a `ClientException` with `statusCode == 0` (or the gateway status, for example 503).

```dart
// Cache-first for instant UI
final stream = client.collection('posts').watchRecords(
  requestPolicy: RequestPolicy.cacheFirst,
);

// Network-first for critical data
final stream = client.collection('orders').watchRecords(
  requestPolicy: RequestPolicy.networkFirst,
);
```

## Handling Empty Streams

Streams can emit empty lists:

```dart
final postsProvider = StreamProvider<List<RecordModel>>((ref) {
  final client = ref.watch(pocketbaseProvider);
  return client.collection('posts').watchRecords();
});

// In UI
postsAsync.when(
  data: (posts) {
    if (posts.isEmpty) {
      return EmptyState(
        message: 'No posts yet',
        onAction: () => AppRouter.pushCreatePost(context),
      );
    }
    return ListView.builder(...);
  },
  loading: () => ...,
  error: (e, s) => ...,
);
```

## Optimistic Updates

Changes made locally emit to streams immediately:

```dart
// In provider/repository
await client.collection('posts').create(
  body: {'title': 'New Post'},
  requestPolicy: RequestPolicy.cacheFirst, // Writes to cache first
);
// Stream immediately emits with new post, even before server confirms

// UI updates instantly because stream watches local cache
```

## Multiple Streams

You can have multiple streams watching the same collection with different filters:

```dart
// All published posts
final publishedPostsProvider = StreamProvider((ref) {
  return client.collection('posts').watchRecords(filter: "published = true");
});

// My drafts
final myDraftsProvider = StreamProvider((ref) {
  final userId = ref.watch(currentUserIdProvider);
  return client.collection('posts').watchRecords(
    filter: "author = '$userId' && published = false",
  );
});

// Both streams update independently based on their filters
```
