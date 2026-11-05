# Search

This guide covers full-text search using FTS5.

## Overview

pocketbase_drift includes integrated Full-Text Search (FTS5) for fast local searches across cached record data. Search works entirely offline against the local cache.

## Basic Search

### Search Within Collection

```dart
// Search all fields in 'posts' collection
final results = await client.collection('posts').search('flutter').get();

for (final post in results) {
  print(post.get<String>('title'));
}
```

### Search Across All Collections

```dart
// Global search across all cached data
final results = await client.search('flutter').get();

for (final record in results) {
  print('${record.service}: ${record.id}');
}
```

## Reactive Search Streams

```dart
// Watch search results (updates when data changes)
final stream = client.collection('posts').search('flutter').watch();

stream.listen((results) {
  print('Found ${results.length} matches');
});
```

## Search Operators

FTS5 supports various search operators:

```dart
// Exact phrase
await client.collection('posts').search('"flutter widgets"').get();

// AND (implicit)
await client.collection('posts').search('flutter dart').get();

// OR
await client.collection('posts').search('flutter OR react').get();

// NOT
await client.collection('posts').search('flutter NOT web').get();

// Prefix matching
await client.collection('posts').search('flut*').get();
```

## Using with Riverpod

```dart
// Search provider with debouncing
final searchQueryProvider = StateProvider<String>((ref) => '');

final searchResultsProvider = StreamProvider<List<RecordModel>>((ref) {
  final query = ref.watch(searchQueryProvider);
  final client = ref.watch(pocketbaseProvider);
  
  if (query.isEmpty) {
    return Stream.value([]);
  }
  
  return client.collection('posts').search(query).watch();
});

// In UI
class SearchScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final results = ref.watch(searchResultsProvider);
    
    return Column(
      children: [
        TextField(
          onChanged: (value) {
            ref.read(searchQueryProvider.notifier).state = value;
          },
          decoration: const InputDecoration(
            hintText: 'Search posts...',
            prefixIcon: Icon(Icons.search),
          ),
        ),
        Expanded(
          child: results.when(
            data: (posts) => ListView.builder(
              itemCount: posts.length,
              itemBuilder: (context, index) => PostCard(post: posts[index]),
            ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, s) => ErrorView(message: e.toString()),
          ),
        ),
      ],
    );
  }
}
```

## Debounced Search

Debounce rapid typing:

```dart
// Debounced search query
final debouncedSearchProvider = StateProvider<String>((ref) => '');

// Debounce timer
Timer? _debounce;

void onSearchChanged(WidgetRef ref, String query) {
  _debounce?.cancel();
  _debounce = Timer(const Duration(milliseconds: 300), () {
    ref.read(debouncedSearchProvider.notifier).state = query;
  });
}

// Search results based on debounced query
final searchResultsProvider = StreamProvider<List<RecordModel>>((ref) {
  final query = ref.watch(debouncedSearchProvider);
  final client = ref.watch(pocketbaseProvider);
  
  if (query.length < 2) {
    return Stream.value([]);
  }
  
  return client.collection('posts').search(query).watch();
});
```

## Search with Filtering

Combine search with filters:

```dart
// First search, then filter results
final results = await client.collection('posts').search('flutter').get();

// Further filter in Dart
final publishedResults = results.where((post) => 
  post.data['published'] == true
).toList();
```

## Search Scope

Search covers all text fields in the record's JSON data:
- All string fields
- Nested JSON content
- Does not search relation IDs (just the raw ID string)

Search excludes:
- Records deleted offline whose deletion is not synced yet
- Unsynced changes of other accounts. After logout, pending changes stay in the cache (`pendingOwner`), but only the account that wrote them sees them in search results.
- The sync bookkeeping keys: `retryCount`, `pendingFields`, `pendingFiles`, `pendingOwner`, `pendingRev`, `syncError`, `pendingBase`, `baseUpdated`, `pendingDeltas` are not indexed (`synced`, `isNew`, `deleted` and `noSync` stay). A record with a pending local edit is found by its new value, not by its old value in `pendingBase`.

An open `search(...).watch()` re-runs on every write to the `services` table, follows an account switch without a new listen, and completes when the database closes.

The FTS5 table `text_entries` uses external content (`services`). Triggers keep it current and leave out the bookkeeping keys. **Do not run the FTS5 `rebuild` command** on it: it would index the raw JSON, bookkeeping keys included. The v4 migration re-indexes all records.

## Performance Tips

### Limit Results

```dart
// Take only first 20 results
final results = await client.collection('posts').search('flutter').get();
final limited = results.take(20).toList();
```

### Minimum Query Length

```dart
if (query.length < 2) {
  return []; // Too short, skip search
}
```

### Search Specific Collections

```dart
// More efficient than global search
final postResults = await client.collection('posts').search(query).get();

// Only global search when needed
if (needsGlobalSearch) {
  final globalResults = await client.search(query).get();
}
```

## Example: Search Screen

```dart
class SearchScreen extends ConsumerStatefulWidget {
  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _controller.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      ref.read(searchQueryProvider.notifier).state = query;
    });
  }

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(searchResultsProvider);
    final query = ref.watch(searchQueryProvider);

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          onChanged: _onSearchChanged,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Search...',
            border: InputBorder.none,
          ),
        ),
        actions: [
          if (_controller.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                _controller.clear();
                ref.read(searchQueryProvider.notifier).state = '';
              },
            ),
        ],
      ),
      body: query.isEmpty
          ? const Center(child: Text('Enter a search term'))
          : results.when(
              data: (posts) {
                if (posts.isEmpty) {
                  return Center(child: Text('No results for "$query"'));
                }
                return ListView.builder(
                  itemCount: posts.length,
                  itemBuilder: (context, index) => ListTile(
                    title: Text(posts[index].get<String>('title') ?? ''),
                    onTap: () => AppRouter.pushPostDetail(context, posts[index].id),
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, s) => Center(child: Text('Error: $e')),
            ),
    );
  }
}
```
