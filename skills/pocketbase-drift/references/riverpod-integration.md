# Riverpod Integration

This guide covers provider patterns for pocketbase_drift.

## Core Providers

### Dependencies

```dart
// lib/shared/providers/core_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Override in main.dart
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('Override in main.dart');
});
```

### PocketBase Client

Create the client before `runApp` and await `setSchema`. Then override the client provider with it. The example app (`example/lib/shared/providers/pocketbase_provider.dart`) uses this pattern and names the provider `pocketBaseProvider`.

```dart
// lib/shared/providers/pocketbase_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocketbase_drift/pocketbase_drift.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Creates the client and caches the schema before it returns.
/// setSchema throws on invalid schema JSON.
Future<$PocketBase> createPocketBaseClient(
  SharedPreferences prefs,
  String schemaJson,
) async {
  final client = $PocketBase.database(
    const String.fromEnvironment('POCKETBASE_URL',
      defaultValue: 'http://127.0.0.1:8090'),
    authStore: $AuthStore.prefs(prefs, 'pb_auth'),
  );
  await client.setSchema(schemaJson);
  return client;
}

// Override in main.dart with the client from createPocketBaseClient
final pocketbaseProvider = Provider<$PocketBase>((ref) {
  throw UnimplementedError('Override in main.dart');
});
```

### Main.dart Setup

```dart
// lib/main.dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final startupValues = await Future.wait([
    SharedPreferences.getInstance(),
    rootBundle.loadString('assets/pb_schema.json'),
  ]);
  
  final prefs = startupValues[0] as SharedPreferences;
  final schema = startupValues[1] as String;

  final client = await createPocketBaseClient(prefs, schema);

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        pocketbaseProvider.overrideWith((ref) {
          ref.onDispose(client.close);
          return client;
        }),
      ],
      child: const MyApp(),
    ),
  );
}
```

## Authentication Providers

```dart
// lib/shared/providers/auth_provider.dart

// Current user (nullable when not logged in)
final currentUserProvider = StreamProvider<RecordModel?>((ref) {
  final client = ref.watch(pocketbaseProvider);
  
  // Watch auth store changes
  return Stream.periodic(const Duration(seconds: 1)).map((_) {
    if (client.authStore.isValid) {
      return client.authStore.record;
    }
    return null;
  }).distinct();
});

// Simple user ID provider
final currentUserIdProvider = Provider<String?>((ref) {
  return ref.watch(currentUserProvider).valueOrNull?.id;
});

// Is authenticated
final isAuthenticatedProvider = Provider<bool>((ref) {
  return ref.watch(currentUserIdProvider) != null;
});

// Auth controller for login/logout actions
final authControllerProvider = Provider<AuthController>((ref) {
  return AuthController(ref.watch(pocketbaseProvider));
});

class AuthController {
  AuthController(this._client);
  final $PocketBase _client;

  Future<RecordModel> login(String email, String password) async {
    final result = await _client.collection('users').authWithPassword(
      email,
      password,
    );
    return result.record!;
  }

  Future<RecordModel> register({
    required String email,
    required String password,
    required String name,
  }) async {
    await _client.collection('users').create(body: {
      'email': email,
      'password': password,
      'passwordConfirm': password,
      'name': name,
    });
    return login(email, password);
  }

  /// Deletes the cache but keeps this account's unsynced changes.
  /// They sync when the same account logs in again.
  /// Use `_client.db.clearAllData()` to delete them too.
  void logout() {
    _client.authStore.clear();
  }
}
```

## Repository Pattern

### Base Repository

```dart
// lib/shared/repositories/base_repository.dart
abstract class BaseRepository<T> {
  BaseRepository(this.client, this.collectionName);
  
  final $PocketBase client;
  final String collectionName;
  
  $RecordService get collection => client.collection(collectionName);
  
  Stream<List<RecordModel>> watchAll({
    String? filter,
    String? sort,
    String? expand,
    int? limit, // Fetches only `limit` records from the server
    RequestPolicy requestPolicy = RequestPolicy.cacheAndNetwork,
  }) {
    return collection.watchRecords(
      filter: filter,
      sort: sort,
      expand: expand,
      limit: limit,
      requestPolicy: requestPolicy,
    );
  }

  // Use watchRecordsState for loading and error state (QueryState).
  // An unreachable server is not an error for cache-backed queries.
  Stream<QueryState<List<RecordModel>>> watchAllState({
    String? filter,
    String? sort,
  }) {
    return collection.watchRecordsState(filter: filter, sort: sort);
  }
  
  Stream<RecordModel?> watchOne(String id, {String? expand}) {
    return collection.watchRecord(id, expand: expand);
  }
  
  Future<RecordModel> create(Map<String, dynamic> data) {
    return collection.create(
      body: data,
      requestPolicy: RequestPolicy.cacheAndNetwork,
    );
  }
  
  Future<RecordModel> update(String id, Map<String, dynamic> data) {
    return collection.update(
      id,
      body: data,
      requestPolicy: RequestPolicy.cacheAndNetwork,
    );
  }
  
  Future<void> delete(String id) {
    return collection.delete(
      id,
      requestPolicy: RequestPolicy.cacheAndNetwork,
    );
  }
}
```

### Feature Repository

```dart
// lib/features/posts/repositories/post_repository.dart
class PostRepository extends BaseRepository<Post> {
  PostRepository($PocketBase client) : super(client, 'posts');
  
  Stream<List<RecordModel>> watchPublished() {
    return watchAll(
      filter: "published = true",
      sort: '-created',
      expand: 'author',
    );
  }
  
  Stream<List<RecordModel>> watchByAuthor(String authorId) {
    return watchAll(
      filter: "author = '$authorId'",
      sort: '-created',
    );
  }
  
  Future<RecordModel> publish(String postId) {
    return update(postId, {'published': true});
  }
}

// Provider
final postRepositoryProvider = Provider<PostRepository>((ref) {
  return PostRepository(ref.watch(pocketbaseProvider));
});
```

## Stream Providers

```dart
// lib/features/posts/providers/post_providers.dart

// All posts
final postsProvider = StreamProvider<List<RecordModel>>((ref) {
  final repo = ref.watch(postRepositoryProvider);
  return repo.watchPublished();
});

// Posts by current user
final myPostsProvider = StreamProvider<List<RecordModel>>((ref) {
  final repo = ref.watch(postRepositoryProvider);
  final userId = ref.watch(currentUserIdProvider);
  
  if (userId == null) {
    return Stream.value([]);
  }
  
  return repo.watchByAuthor(userId);
});

// Single post
final postProvider = StreamProvider.family<RecordModel?, String>((ref, postId) {
  final repo = ref.watch(postRepositoryProvider);
  return repo.watchOne(postId, expand: 'author,tags');
});
```

## Action Providers

For mutations (create, update, delete):

```dart
// lib/features/posts/providers/post_actions_provider.dart

final postActionsProvider = Provider<PostActions>((ref) {
  return PostActions(ref.watch(postRepositoryProvider));
});

class PostActions {
  PostActions(this._repo);
  final PostRepository _repo;

  Future<RecordModel> create({
    required String title,
    required String content,
    required String authorId,
  }) async {
    return _repo.create({
      'title': title,
      'content': content,
      'author': authorId,
      'published': false,
    });
  }

  Future<RecordModel> update(String id, {String? title, String? content}) async {
    final data = <String, dynamic>{};
    if (title != null) data['title'] = title;
    if (content != null) data['content'] = content;
    return _repo.update(id, data);
  }

  Future<RecordModel> publish(String id) => _repo.publish(id);
  
  Future<void> delete(String id) => _repo.delete(id);
}
```

## UI Usage

```dart
class PostListScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final postsAsync = ref.watch(postsProvider);
    
    return Scaffold(
      appBar: AppBar(title: const Text('Posts')),
      body: postsAsync.when(
        data: (posts) {
          if (posts.isEmpty) {
            return const EmptyState(message: 'No posts yet');
          }
          return ListView.builder(
            itemCount: posts.length,
            itemBuilder: (context, index) => PostCard(post: posts[index]),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, s) => ErrorView(
          message: e.toString(),
          onRetry: () => ref.invalidate(postsProvider),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _createPost(ref),
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _createPost(WidgetRef ref) async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;
    
    await ref.read(postActionsProvider).create(
      title: 'New Post',
      content: 'Content here',
      authorId: userId,
    );
  }
}
```

## Connectivity Provider

```dart
// Each new listener gets the current status first, then only changes.
final connectivityProvider = StreamProvider<bool>((ref) {
  final client = ref.watch(pocketbaseProvider);
  return client.connectivity.statusStream;
});

// Usage in widget
final isConnected = ref.watch(connectivityProvider).valueOrNull ?? true;

if (!isConnected) {
  return OfflineBanner();
}
```

## Pending Sync Provider

```dart
// Live queue of pending changes across all collections.
// Excludes local-only rows and other accounts' rows. Includes parked rows.
final pendingChangesProvider = StreamProvider<List<Service>>((ref) {
  final client = ref.watch(pocketbaseProvider);
  return client.db.pendingRecords().watch();
});

// Show sync indicator
final pendingCount = ref.watch(pendingChangesProvider).valueOrNull?.length ?? 0;
if (pendingCount > 0) {
  Badge(
    label: Text('$pendingCount'),
    child: Icon(Icons.cloud_upload),
  );
}
```

## Sync Failures Provider

```dart
// Changes the server rejected localSyncRetryCount times (parked),
// or offline edits of records deleted on the server (dropped).
final syncFailuresProvider = StreamProvider<SyncFailure>((ref) {
  final client = ref.watch(pocketbaseProvider);
  return client.syncFailures;
});

// Show each failure once
ref.listen(syncFailuresProvider, (previous, next) {
  final failure = next.valueOrNull;
  if (failure == null) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text('Not synced: ${failure.collection}/${failure.recordId}'),
  ));
});

// Actions
final client = ref.read(pocketbaseProvider);
await client.syncPendingChanges(includeFailed: true); // Retry parked changes
await client.discardPendingChange('posts', recordId); // Drop one local change
```

## Widget Tests

Create the client in `setUp`, outside the fake-async zone of `testWidgets`. Then `await client.syncCompleted` in `setUp`. A database query that still runs on real time blocks the queries of the fake-async zone. Override `pocketbaseProvider` with this client in the test's `ProviderScope`. See `setup.md` for a full example.

## Summary

| Provider Type | Use For |
|---------------|---------|
| `Provider` | Services, repositories, controllers |
| `StreamProvider` | Reactive data from `watchRecords`/`watchRecord` |
| `StreamProvider.family` | Parameterized streams (by ID, filter) |
| `FutureProvider` | One-time async operations |
| `StateNotifierProvider` | Complex state with mutations |

**Key Pattern:** Repositories wrap `$RecordService`, providers expose streams to UI.
