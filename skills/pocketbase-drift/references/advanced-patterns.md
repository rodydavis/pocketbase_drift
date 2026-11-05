# Advanced Patterns

This guide covers advanced patterns for pocketbase_drift including auth flows, optimistic updates, pagination, and troubleshooting.

## Model Factory Patterns

### Complete Model with RecordModel Helpers

```dart
class Post {
  const Post({
    required this.id,
    required this.title,
    required this.content,
    required this.authorId,
    this.author,
    this.tags = const [],
    required this.published,
    required this.created,
    required this.updated,
  });
  
  final String id;
  final String title;
  final String content;
  final String authorId;
  final User? author;
  final List<String> tags;
  final bool published;
  final DateTime created;
  final DateTime updated;
  
  factory Post.fromRecord(RecordModel record) {
    // Use dot notation for expanded relations (record.expand is deprecated)
    final expandedAuthor = record.get<RecordModel>('expand.author');
    
    return Post(
      id: record.id,
      title: record.getStringValue('title'),
      content: record.getStringValue('content'),
      authorId: record.getStringValue('authorId'),
      author: expandedAuthor != null ? User.fromRecord(expandedAuthor) : null,
      tags: record.getListValue<String>('tags'),
      published: record.getBoolValue('published'),
      created: DateTime.parse(record.get('created')),
      updated: DateTime.parse(record.get('updated')),
    );
  }
  
  Map<String, dynamic> toMap() => {
    'title': title,
    'content': content,
    'authorId': authorId,
    'tags': tags,
    'published': published,
  };
  
  Post copyWith({
    String? title,
    String? content,
    List<String>? tags,
    bool? published,
  }) {
    return Post(
      id: id,
      title: title ?? this.title,
      content: content ?? this.content,
      authorId: authorId,
      author: author,
      tags: tags ?? this.tags,
      published: published ?? this.published,
      created: created,
      updated: updated,
    );
  }
}
```

## Advanced Auth Flow

### Token Refresh Logic

```dart
class AuthRepository {
  AuthRepository(this._client);
  final $PocketBase _client;

  User? get currentUser {
    final record = _client.authStore.record;
    if (record == null) return null;
    return User.fromMap(record.toJson());
  }

  bool get isAuthenticated => _client.authStore.isValid;

  DateTime? _getTokenExpiration() {
    final token = _client.authStore.token;
    if (token.isEmpty) return null;

    try {
      // JWT format: header.payload.signature
      final parts = token.split('.');
      if (parts.length != 3) return null;

      // Decode payload (base64)
      final payload = parts[1];
      final normalized = base64.normalize(payload);
      final decoded = utf8.decode(base64.decode(normalized));
      final json = jsonDecode(decoded);

      // Extract exp (Unix timestamp in seconds)
      final exp = json['exp'] as int?;
      if (exp == null) return null;

      return DateTime.fromMillisecondsSinceEpoch(exp * 1000);
    } catch (e) {
      return null; // Decode error, assume needs refresh
    }
  }

  bool shouldRefreshToken() {
    if (!_client.authStore.isValid) return false;

    final expiresAt = _getTokenExpiration();
    if (expiresAt == null) return true; // Can't decode, refresh to be safe

    final now = DateTime.now();
    const threshold = Duration(days: 1);
    return expiresAt.difference(now) <= threshold;
  }

  Future<void> refreshToken() async {
    await _client.collection('users').authRefresh();
  }
}
```

### Auth State Notifier with Auto-Refresh

```dart
class AuthStateNotifier extends StateNotifier<AsyncValue<User?>> {
  AuthStateNotifier(this._authRepository) : super(const AsyncValue.data(null)) {
    _init();
  }

  final AuthRepository _authRepository;

  void _init() {
    final user = _authRepository.currentUser;
    state = AsyncValue.data(user);
    _refreshTokenIfNeeded();
  }

  Future<void> _refreshTokenIfNeeded() async {
    if (!_authRepository.shouldRefreshToken()) return;

    try {
      await _authRepository.refreshToken();
    } catch (e) {
      // Token refresh failed, logout user
      logout();
    }
  }

  Future<void> login(String email, String password) async {
    state = const AsyncValue.loading();
    try {
      final user = await _authRepository.login(email, password);
      state = AsyncValue.data(user);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }

  void logout() {
    _authRepository.logout();
    state = const AsyncValue.data(null);
  }
}
```

## Optimistic Updates

UI updates immediately, reverts on error:

```dart
class LikeNotifier extends StateNotifier<Post> {
  LikeNotifier(this._repository, super.post);
  
  final PostRepository _repository;

  Future<void> toggleLike() async {
    final previousState = state;
    
    // Optimistically update UI
    state = state.copyWith(isLiked: !state.isLiked);
    
    try {
      await _repository.update(state.id, {'liked': state.isLiked});
    } catch (e) {
      // Revert on error
      state = previousState;
      rethrow;
    }
  }
}
```

With `RequestPolicy.cacheAndNetwork`, the write throws only when the server rejects it (for example 400 or 403). Nothing is stored in that case, so the revert is correct. When the server is unreachable, the write is queued locally and does not throw.

## Infinite Scroll

```dart
class PostListState {
  const PostListState({
    this.posts = const [],
    this.isLoading = false,
    this.hasMore = true,
    this.error,
  });
  
  final List<Post> posts;
  final bool isLoading;
  final bool hasMore;
  final String? error;
  
  PostListState copyWith({
    List<Post>? posts,
    bool? isLoading,
    bool? hasMore,
    String? error,
  }) {
    return PostListState(
      posts: posts ?? this.posts,
      isLoading: isLoading ?? this.isLoading,
      hasMore: hasMore ?? this.hasMore,
      error: error,
    );
  }
}

class PostListNotifier extends StateNotifier<PostListState> {
  PostListNotifier(this._repository) : super(const PostListState()) {
    loadMore(); // Initial load
  }
  
  final PostRepository _repository;
  int _currentPage = 0;
  static const _pageSize = 20;

  Future<void> loadMore() async {
    if (state.isLoading || !state.hasMore) return;
    
    state = state.copyWith(isLoading: true, error: null);
    
    try {
      final newPosts = await _repository.getPage(
        page: _currentPage + 1,
        perPage: _pageSize,
      );
      
      if (newPosts.isEmpty || newPosts.length < _pageSize) {
        state = state.copyWith(
          posts: [...state.posts, ...newPosts],
          hasMore: false,
          isLoading: false,
        );
      } else {
        _currentPage++;
        state = state.copyWith(
          posts: [...state.posts, ...newPosts],
          isLoading: false,
        );
      }
    } catch (e) {
      state = state.copyWith(
        isLoading: false, 
        error: e.toString(),
      );
    }
  }

  Future<void> refresh() async {
    _currentPage = 0;
    state = const PostListState();
    await loadMore();
  }
}

final postListProvider = StateNotifierProvider<PostListNotifier, PostListState>((ref) {
  return PostListNotifier(ref.watch(postRepositoryProvider));
});
```

### Infinite Scroll UI

```dart
class PostListScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(postListProvider);
    
    return RefreshIndicator(
      onRefresh: () => ref.read(postListProvider.notifier).refresh(),
      child: ListView.builder(
        itemCount: state.posts.length + (state.hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= state.posts.length) {
            // Load more trigger
            if (!state.isLoading) {
              ref.read(postListProvider.notifier).loadMore();
            }
            return const Center(child: CircularProgressIndicator());
          }
          return PostCard(post: state.posts[index]);
        },
      ),
    );
  }
}
```

## Pull-to-Refresh

```dart
class PostListScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final postsAsync = ref.watch(postsProvider);
    
    return RefreshIndicator(
      onRefresh: () async {
        // Fetch from the server and write the result to the cache.
        // networkOnly reads do not write the cache.
        final repository = ref.read(postRepositoryProvider);
        await repository.getAll(
          requestPolicy: RequestPolicy.networkFirst,
        );
        // Rebuild stream with new data
        ref.invalidate(postsProvider);
      },
      child: postsAsync.when(
        data: (posts) => ListView.builder(
          itemCount: posts.length,
          itemBuilder: (context, index) => PostCard(post: posts[index]),
        ),
        loading: () => const LoadingView(),
        error: (e, s) => ErrorView(error: e),
      ),
    );
  }
}
```

## Error Handling

Server answers are never hidden behind the cache. Catch `ClientException` and check `statusCode`:

```dart
try {
  final post = await client.collection('posts').getOne(postId);
} on ClientException catch (e) {
  if (e.statusCode == 0) {
    // Server unreachable and the record is not cached.
  } else if (e.statusCode == 404) {
    // The server answered: the record does not exist.
  } else if (e.statusCode == 403) {
    // The server answered: no access.
  }
}
```

Rules:
- Reads fall back to the cache only when the server is unreachable: status 0, timeout, socket error, 408, 429 or 5xx.
- 4xx answers (400, 401, 403, 404) are thrown with the server status.
- When nothing is cached and the server is unreachable, reads throw `ClientException` with status 0 (or the gateway status, for example 503).
- `cacheAndNetwork` writes are queued locally only when the server is unreachable. A rejection (400 validation, 403 rule) is thrown, and nothing is stored.
- `networkFirst` and `networkOnly` writes throw on failure. Status 0 means that the server is unreachable (no connection, socket error, or `requestTimeout` elapsed; `originalError` holds the cause). A 502, 503 or 504 answer keeps the server's status. `networkFirst` update does not change a 404 or 400 into a create.
- `cacheFirst` writes do not throw server rejections. Rejections count towards `localSyncRetryCount`. Parked changes are reported on `client.syncFailures`.

### Request Timeout

`requestTimeout` (default 15 seconds) limits single-record reads and writes without file uploads. When it elapses, offline-first writes are queued and reads fall back to the cache. `null` disables the limit.

```dart
final client = $PocketBase.database(
  'https://example.pocketbase.io',
  requestTimeout: const Duration(seconds: 8),
);
```

## Batch Operations

```dart
import 'package:http/http.dart' as http;

final batch = client.$createBatch();
batch.collection('posts').create(
  body: {'title': 'New Post'},
  files: [http.MultipartFile.fromBytes('image', bytes, filename: 'a.jpg')],
);
batch.collection('posts').update(postId, body: {'title': 'Edited'});
batch.collection('posts').delete(oldPostId);

try {
  final results = await batch.send(); // RequestPolicy.cacheAndNetwork
  for (final result in results) {
    if (result.isError) {
      print('${result.collection}/${result.recordId}: ${result.status}');
    }
  }
} on ClientException catch (e) {
  // The server rejected the batch. Nothing was stored.
}
```

Batch rules:
- Creates and upserts without an `id` get a client-generated id.
- Files are sent with the batch. When the batch is queued offline, the files are stored and sent during sync.
- `cacheAndNetwork`: a rejected batch throws, and nothing is stored. Only an unreachable server queues the operations. Each queued operation syncs individually. A queued delete of a record that is not cached returns status 204.
- `networkOnly` and `networkFirst`: when the device is offline, `send` throws `ClientException` with status 0. `networkOnly` updates the cache only for records with a queued local change.
- `cacheFirst`: the operations are written to the cache as pending and sent in the background.
- A batch update of a record with an unsynced local change does not mark the whole change as synced. Fields, increments and uploads that the batch did not send still sync. A value that the batch set is not overwritten later by the older queued value. An edit made while an online batch is in flight stays pending, also when it restores the old value. A field that the batch sent is done also when the server stores it in another form (dates) or does not return it (`password`). With `fields:`, the cached record keeps its other fields.

## Sync Status and Failures

### Manual Sync

Sync runs automatically at startup, when the server becomes reachable, on app resume and after login. To start a pass manually:

```dart
await client.syncPendingChanges();
```

`syncPendingChanges` never throws. Only one pass runs at a time. A call during a pass returns a future that completes after one more pass. `client.syncCompleted` completes when the running pass ends.

### Pending Changes Badge

```dart
final pendingCountProvider = StreamProvider<int>((ref) {
  final client = ref.watch(pocketbaseProvider);
  return client.db.pendingRecords().watch().map((rows) => rows.length);
});
```

`pendingRecords()` excludes local-only rows and rows of other accounts. It includes rows parked with `syncError`. Use `pendingRecords(service: 'posts')` for one collection.

### Sync Failures

After `localSyncRetryCount` (default 5) rejections, a change is parked. The row keeps a `syncError` map (`status`, `message`, `data`, `at`). Automatic sync skips it. The record stays visible in reads.

```dart
final subscription = client.syncFailures.listen((failure) {
  if (failure.dropped) {
    // The record was deleted on the server. The local edit was discarded.
    showMessage('${failure.collection}/${failure.recordId} no longer exists');
    return;
  }
  // failure.operation: SyncOperation.create | update | delete
  showMessage('Sync rejected (${failure.statusCode}): ${failure.error}');
});

// Retry parked changes (for example after the user fixed the data)
Future<void> retryParked() => client.syncPendingChanges(includeFailed: true);

// Or discard one parked change. The next read loads the server version.
Future<void> discard(SyncFailure failure) =>
    client.discardPendingChange(failure.collection, failure.recordId);
```

List the parked rows:

```dart
final parked = (await client.db.pendingRecords().get())
    .where((row) => row.data[RecordMeta.syncError] != null)
    .toList();
```

## Troubleshooting

### Changes Not Syncing

```dart
// Check whether the server is reachable
if (!client.connectivity.canReachServer) {
  print('Server not reachable');
}

// Check pending items (parked rows have a syncError)
final pending = await client.collection('posts').pending().get();
print('Pending: ${pending.length}');

// Manually trigger sync (includeFailed also retries parked changes)
await client.syncPendingChanges(includeFailed: true);
```

Pending changes belong to the account that wrote them (`pendingOwner`). They do not sync while another account is logged in.

### Schema Validation Errors

```dart
// Ensure schema is cached. setSchema throws on invalid schema JSON.
await client.setSchema(schemaJson);

// Check collections exist
final collections = await client.db.$collections().get();
print('Collections: ${collections.map((c) => c.name).toList()}');
```

### File Not Found in Cache

```dart
// Force network fetch for missing files
final bytes = await client.files.getFileBytes(
  recordId: id,
  recordCollectionName: 'posts',
  filename: filename,
  requestPolicy: RequestPolicy.networkOnly,
);
```

## Security Considerations

### Data Sanitization

```dart
class PostRepository {
  Future<Post> create(Map<String, dynamic> data) async {
    // Sanitize user input before saving
    final sanitized = {
      'title': _sanitize(data['title'] as String? ?? ''),
      'content': _sanitize(data['content'] as String? ?? ''),
      // Don't allow users to set server-controlled fields
    };
    
    final record = await _client.collection('posts').create(
      body: sanitized,
      requestPolicy: RequestPolicy.cacheAndNetwork,
    );
    
    return Post.fromRecord(record);
  }
  
  String _sanitize(String input) {
    return input
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .trim();
  }
}
```

## Testing Helpers

### In-Memory Client for Tests

```dart
class TestHelpers {
  static $PocketBase createTestClient() {
    return $PocketBase.database(
      'http://test.pocketbase.io',
      inMemory: true, // No persistence
    );
  }
  
  static Future<void> seedTestData(
    $PocketBase client,
    String collection,
    List<Map<String, dynamic>> data,
  ) async {
    for (final item in data) {
      await client.db.$create(collection, {
        ...item,
        'synced': true,
      });
    }
  }
  
  static Future<void> clearTestData($PocketBase client) async {
    await client.db.clearAllData();
  }
}

// Usage in tests
void main() {
  late $PocketBase testClient;
  late PostRepository repository;

  setUp(() async {
    testClient = TestHelpers.createTestClient();
    // Wait for the startup sync pass.
    await testClient.syncCompleted;
    repository = PostRepository(testClient);
  });

  tearDown(() async {
    await TestHelpers.clearTestData(testClient);
    testClient.close();
  });

  test('getAll returns seeded posts', () async {
    await TestHelpers.seedTestData(testClient, 'posts', [
      {'id': '1', 'title': 'Test Post'},
      {'id': '2', 'title': 'Another Post'},
    ]);
    
    final posts = await repository.getAll(
      requestPolicy: RequestPolicy.cacheOnly,
    );
    
    expect(posts, hasLength(2));
    expect(posts.first.title, 'Test Post');
  });
}
```

An `inMemory: true` client runs SQLite on the calling isolate. The default (non-web) client runs SQLite in a background isolate.

For widget tests, create the client outside the fake-async zone (in `setUp`, not inside `testWidgets`). Then `await client.syncCompleted` in `setUp`. A database query that still runs on real time blocks the queries in the fake-async zone.

## Complete Todo App Example

```dart
// models/todo.dart
class Todo {
  const Todo({
    required this.id,
    required this.title,
    required this.completed,
    required this.created,
    required this.updated,
  });
  
  final String id;
  final String title;
  final bool completed;
  final DateTime created;
  final DateTime updated;
  
  factory Todo.fromRecord(RecordModel record) {
    return Todo(
      id: record.id,
      title: record.getStringValue('title'),
      completed: record.getBoolValue('completed'),
      created: DateTime.parse(record.get('created')),
      updated: DateTime.parse(record.get('updated')),
    );
  }
  
  Map<String, dynamic> toMap() => {
    'title': title,
    'completed': completed,
  };
}

// repositories/todo_repository.dart
final todoRepositoryProvider = Provider<TodoRepository>((ref) {
  return TodoRepository(ref.watch(pocketbaseProvider));
});

class TodoRepository {
  TodoRepository(this._client);
  final $PocketBase _client;
  
  Stream<List<Todo>> watchAll() {
    return _client.collection('todos')
      .watchRecords(sort: '-created')
      .map((records) => records.map(Todo.fromRecord).toList());
  }
  
  Future<Todo> create(String title) async {
    final record = await _client.collection('todos').create(
      body: {'title': title, 'completed': false},
    );
    return Todo.fromRecord(record);
  }
  
  Future<Todo> toggleCompleted(String id, bool completed) async {
    final record = await _client.collection('todos').update(
      id,
      body: {'completed': completed},
    );
    return Todo.fromRecord(record);
  }
  
  Future<void> delete(String id) async {
    await _client.collection('todos').delete(id);
  }
}

// providers/todo_providers.dart
final todosProvider = StreamProvider<List<Todo>>((ref) {
  return ref.watch(todoRepositoryProvider).watchAll();
});

// screens/todo_list_screen.dart
class TodoListScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final todosAsync = ref.watch(todosProvider);
    
    return Scaffold(
      appBar: AppBar(title: const Text('Todos')),
      body: todosAsync.when(
        data: (todos) => ListView.builder(
          itemCount: todos.length,
          itemBuilder: (context, index) => TodoTile(todo: todos[index]),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, s) => Center(child: Text('Error: $e')),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addTodo(context, ref),
        child: const Icon(Icons.add),
      ),
    );
  }
  
  void _addTodo(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Todo'),
        content: TextField(
          autofocus: true,
          onSubmitted: (value) {
            ref.read(todoRepositoryProvider).create(value);
            Navigator.pop(context);
          },
        ),
      ),
    );
  }
}

class TodoTile extends ConsumerWidget {
  const TodoTile({super.key, required this.todo});
  final Todo todo;
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      title: Text(
        todo.title,
        style: TextStyle(
          decoration: todo.completed ? TextDecoration.lineThrough : null,
        ),
      ),
      leading: Checkbox(
        value: todo.completed,
        onChanged: (value) {
          ref.read(todoRepositoryProvider).toggleCompleted(
            todo.id,
            value ?? false,
          );
        },
      ),
      trailing: IconButton(
        icon: const Icon(Icons.delete),
        onPressed: () {
          ref.read(todoRepositoryProvider).delete(todo.id);
        },
      ),
    );
  }
}
```
