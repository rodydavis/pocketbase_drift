# Sync & Retry

This guide covers offline synchronization, pending records, and automatic retry.

## How Sync Works

When using `cacheAndNetwork` or `cacheFirst` policies:

### When Online
1. Operations are sent to the server
2. On success, local cache is updated with server response
3. Records marked as `synced: true`

### When Offline (or Network Failure)
1. Operations are applied to local cache immediately
2. Records marked with sync metadata
3. UI updates instantly (optimistic)
4. When connectivity returns, automatic retry begins

## Sync Metadata

Records have these sync-related fields in their `data`:

| Field | Type | Description |
|-------|------|-------------|
| `synced` | bool | `true` if matches server |
| `isNew` | bool | `true` if created offline |
| `deleted` | bool | `true` if marked for deletion |
| `noSync` | bool | `true` if local-only (never syncs) |

## Checking Sync Status

```dart
final post = await client.collection('posts').getOne(postId);

// Check sync status
final synced = post.data['synced'] as bool? ?? true;
final isNew = post.data['isNew'] as bool? ?? false;
final deleted = post.data['deleted'] as bool? ?? false;
final noSync = post.data['noSync'] as bool? ?? false;

// Interpret status
if (synced) {
  print('Fully synced with server');
} else if (noSync) {
  print('Local-only, will never sync');
} else if (isNew) {
  print('Created offline, pending sync');
} else if (deleted) {
  print('Marked for deletion, pending sync');
} else {
  print('Updated offline, pending sync');
}
```

## Automatic Retry

pocketbase_drift automatically retries pending changes when:
- Network connectivity is restored
- App resumes from background

```dart
// This happens automatically, but you can observe it:
client.logging = true; // See sync logs

// Logs will show:
// INFO: Connectivity restored. Retrying all pending local changes.
// INFO: Starting retry for 3 pending items in service: posts
// FINE: Successfully synced new item with ID abc123
// INFO: Completed retry for service: posts
```

## Manual Retry

Trigger retry for a specific collection:

```dart
// Get pending records
final pending = await client.collection('posts').pending().get();
print('${pending.length} records pending sync');

// Manually retry
await for (final progress in client.collection('posts').retryLocal()) {
  print('Progress: ${progress.current}/${progress.total}');
}
```

## Waiting for Sync Completion

```dart
// Wait for all pending syncs to complete
await client.syncCompleted;
print('All syncs complete!');

// Useful before important operations
await client.syncCompleted;
final freshData = await client.collection('posts').getFullList(
  requestPolicy: RequestPolicy.networkOnly,
);
```

## Pending Records Query

Query records that are pending sync:

```dart
// Get all pending (unsynced) records in a collection
final pendingPosts = await client.collection('posts').pending().get();

for (final post in pendingPosts) {
  final isNew = post.data['isNew'] as bool? ?? false;
  final deleted = post.data['deleted'] as bool? ?? false;
  
  if (isNew) {
    print('Pending create: ${post.get<String>('title')}');
  } else if (deleted) {
    print('Pending delete: ${post.id}');
  } else {
    print('Pending update: ${post.get<String>('title')}');
  }
}
```

## UI Sync Indicators

Show users when data is pending sync:

```dart
class PostCard extends StatelessWidget {
  const PostCard({super.key, required this.post});
  final RecordModel post;

  @override
  Widget build(BuildContext context) {
    final synced = post.data['synced'] as bool? ?? true;
    
    return Card(
      child: ListTile(
        title: Text(post.get<String>('title') ?? ''),
        subtitle: Text(post.get<String>('content') ?? ''),
        trailing: synced 
            ? null 
            : const Icon(Icons.cloud_upload, color: Colors.orange),
      ),
    );
  }
}
```

### Sync Status Banner

```dart
class SyncStatusBanner extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(pocketbaseProvider);
    
    return StreamBuilder<bool>(
      stream: client.connectivity.statusStream,
      initialData: client.connectivity.isConnected,
      builder: (context, snapshot) {
        final isConnected = snapshot.data ?? true;
        
        if (isConnected) {
          return const SizedBox.shrink();
        }
        
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          color: Colors.orange,
          child: const Text(
            'Offline - changes will sync when connected',
            style: TextStyle(color: Colors.white),
            textAlign: TextAlign.center,
          ),
        );
      },
    );
  }
}
```

## Connectivity Service

Each client owns a realtime connectivity monitor tuned for PocketBase. It combines three signals: OS interface events (instant triggers), server health probes (`/api/health`) with exponential backoff while offline, and actual request outcomes. When connectivity is restored, the pending-sync retry fires automatically — no app code needed.

```dart
// Current status
final isConnected = client.connectivity.isConnected;

// Whether writes should attempt the network
final canTry = client.connectivity.shouldAttemptNetwork;

// Stream of connectivity changes
client.connectivity.statusStream.listen((isConnected) {
  if (isConnected) {
    print('Now online - pending changes will sync');
  } else {
    print('Now offline');
  }
});
```

Tuning per client (all optional):

```dart
final client = $PocketBase.database(
  'https://your-pb.example.com',
  connectivityProbeTimeout: const Duration(seconds: 5),
  connectivityOnlineProbeInterval: const Duration(seconds: 60),
  connectivityOfflineBackoffMin: const Duration(seconds: 5),
  connectivityOfflineBackoffMax: const Duration(seconds: 60),
);
```

## Deleted Records (Tombstones)

Offline deletes write a local tombstone (`deleted: true`) that stays invisible to all reads (`getFullList`, `getOne`, `watchRecords`, `search`, `$count`) until the sync engine confirms the server deletion. Records created offline and deleted before syncing are purged locally. Raw database access can opt back in:

```dart
// Include tombstones (diagnostics, pending queue views)
await client.db.$query('posts', includeDeleted: true).get();
```

## Conflict Handling

Currently, pocketbase_drift uses "last-write-wins" for conflicts:
- If a record is updated both offline and on server, the sync will use the local version
- Server changes may be overwritten when offline changes sync

For critical data, use `networkFirst` policy to prevent conflicts:

```dart
// Critical updates - require server confirmation
await client.collection('orders').update(
  orderId,
  body: {'status': 'shipped'},
  requestPolicy: RequestPolicy.networkFirst,
);
```

## App Lifecycle Integration

The client automatically handles app lifecycle:

```dart
// When app resumes from background:
// 1. Connectivity subscription is reset
// 2. If online, pending changes are synced

// No manual handling needed, but you can observe:
@override
void didChangeAppLifecycleState(AppLifecycleState state) {
  if (state == AppLifecycleState.resumed) {
    // Client automatically checks for pending syncs
  }
}
```

## Best Practices

### Don't Retry Manually Unless Necessary

```dart
// ✅ Let automatic sync handle it
await client.collection('posts').create(body: data);

// ❌ Don't manually retry on every failure
try {
  await client.collection('posts').create(body: data);
} catch (e) {
  // Automatic retry will handle this
}
```

### Use Appropriate Policies

```dart
// For user content (notes, messages) - use cacheFirst for instant feedback
await client.collection('notes').create(
  body: {'content': note},
  requestPolicy: RequestPolicy.cacheFirst,
);

// For critical data (payments, orders) - use networkFirst
await client.collection('payments').create(
  body: paymentData,
  requestPolicy: RequestPolicy.networkFirst,
);
```

### Inform Users About Sync State

```dart
// Show pending sync count
final pendingCount = await client.collection('posts').pending().get().then((p) => p.length);

ScaffoldMessenger.of(context).showSnackBar(
  SnackBar(content: Text('$pendingCount changes pending sync')),
);
```
