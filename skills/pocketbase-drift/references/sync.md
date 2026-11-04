# Sync & Retry

This guide covers offline synchronization, pending records, and automatic retry.

## How Sync Works

When using `cacheAndNetwork` or `cacheFirst` policies:

### When the Server Answers
1. Operations are sent to the server
2. On success, local cache is updated with server response
3. Records marked as `synced: true`

### When the Server Is Unreachable
"Unreachable" means status 0, timeout, socket error, 408, 429 or 5xx.
1. Operations are applied to local cache immediately
2. Records marked with sync metadata (pending)
3. UI updates instantly (optimistic)
4. When the server is reachable again, the sync engine sends the pending changes

### When the Server Rejects the Write
- `cacheAndNetwork`: The write throws `ClientException` (for example 400 or 403). Nothing is stored. Nothing is queued.
- `cacheFirst`: The change is already in the cache. The rejection is not thrown. It counts towards `localSyncRetryCount` (see "Failed Changes").

## Sync Metadata

Records have these sync-related fields in their `data`. Use the `RecordMeta` constants instead of string keys. The package never sends these keys to the server.

| Field | Type | Description |
|-------|------|-------------|
| `synced` | bool | `true` if matches server. `false` while a local change is pending. A missing key means synced. |
| `isNew` | bool | `true` if created offline |
| `deleted` | bool | `true` if marked for deletion |
| `noSync` | bool | `true` if local-only (never syncs) |
| `retryCount` | int | Sync attempts that the server rejected |
| `pendingFields` | list | Fields changed by pending local updates. Sync sends only these fields. |
| `pendingFiles` | list | Files attached by pending local writes (`{field, name}`) |
| `pendingOwner` | string | Auth record id of the account that made the change |
| `pendingRev` | int | Increments with every local change |
| `syncError` | map | Set when the change is parked: `status`, `message`, `data`, `at` |

Helpers: `RecordMeta.isPending(data)`, `RecordMeta.flag(value)` (reads `true`/`1`), `RecordMeta.strip(data)` (removes the bookkeeping keys).

## Checking Sync Status

Read the cached row. A server response (for example `getOne` with `cacheAndNetwork` while online) does not contain the metadata.

```dart
final post = await client.collection('posts').getOne(
  postId,
  requestPolicy: RequestPolicy.cacheOnly,
);
final data = post.data;

// Interpret status
if (RecordMeta.flag(data[RecordMeta.noSync])) {
  print('Local-only, will never sync');
} else if (!RecordMeta.isPending(data)) {
  print('Fully synced with server');
} else if (data[RecordMeta.syncError] != null) {
  print('Rejected by the server: ${data[RecordMeta.syncError]}');
} else if (RecordMeta.flag(data[RecordMeta.isNew])) {
  print('Created offline, pending sync');
} else {
  print('Updated offline, pending sync');
}
```

Offline deletions are tombstones. Normal reads do not return them (see "Deleted Records").

## Automatic Sync

`client.syncPendingChanges()` sends all pending changes. It runs automatically:
- When the client is created (startup)
- When the server becomes reachable again (`connectivity.statusStream` emits `true`)
- When the app resumes from background (and a network interface is up)
- After login (the auth record id changes to a new non-null value)

Rules of a sync pass:
- **Single-flight:** Only one pass runs at a time. A call during a pass returns a future that completes after one more pass. Changes queued during the pass are included.
- **Order:** Collections sync parents first (by relation fields). Records sync oldest first (by `cachedAt`).
- **Updates are partial:** An update sends only the fields in `pendingFields`. Changes made on other devices to other fields stay on the server.
- **Creates send the whole record.** If an earlier attempt created the record and the response was lost (id already exists), the create becomes an update.
- **Files are sent once:** New files go as multipart parts with the create or update. Later edits do not upload them again.
- **Stops early:** The pass stops when the server becomes unreachable. The remaining changes sync on the next pass.
- **Never throws.** Rejections are reported on `client.syncFailures`.

```dart
// This happens automatically, but you can observe it:
client.logging = true; // See sync logs

// Logs will show:
// INFO: Server reachable. Syncing pending changes.
// INFO: Starting retry for 3 pending items in service: posts
// FINE: Synced create of posts/abc123
// INFO: Completed retry for service: posts
// INFO: Sync pass completed
```

## Manual Sync

Start a sync pass for all collections:

```dart
await client.syncPendingChanges();
```

Retry a specific collection and show progress:

```dart
// Get pending records
final pending = await client.collection('posts').pending().get();
print('${pending.length} records pending sync');

// Manually retry (events can be null)
await for (final progress in client.collection('posts').retryLocal()) {
  if (progress == null) continue;
  print('Progress: ${progress.current}/${progress.total}');
}
```

Push one record and check the result:

```dart
final outcome = await client.collection('posts').pushPending(postId);
final message = switch (outcome) {
  PushOutcome.synced => 'The server accepted the change.',
  PushOutcome.skipped => 'Not pending, parked, or owned by another account.',
  PushOutcome.retryLater => 'Server unreachable or busy. The change stays queued.',
  PushOutcome.rejected => 'The server rejected it. It counts towards the retry limit.',
};
```

Pushes, online writes and batch sends of one record run one at a time. A second `pushPending` call waits for the running push and then sends what is still pending. Changes made while a push is in flight stay pending: an edit keeps the server's names of the files just uploaded, a file attached meanwhile is still uploaded, a delete stays a queued deletion (also for a record whose create is being pushed), and a `cacheOnly` change stays local. An online update removes the fields it set from a queued edit of the same record. It waits at most `requestTimeout` for a running push, so it reaches the server last; after that, `cacheAndNetwork` queues it behind the push and `networkOnly`/`networkFirst` throw `ClientException` with status 0.

## Failed Changes (Parking)

The server can reject a pending change (for example 400 validation or 403 rule). Each rejection increments `retryCount`. After `localSyncRetryCount` rejections (default 5), the change is **parked**:
- The row stays in the cache and stays pending. Reads still show the local version.
- `syncError` holds `status`, `message`, `data` and `at`.
- Automatic sync skips the row.
- `client.syncFailures` emits a `SyncFailure`.

An offline update whose record was deleted on the server is dropped at once. The local copy is removed. `syncFailures` emits a `SyncFailure` with `dropped: true`.

`SyncFailure` fields: `collection`, `recordId`, `operation` (`SyncOperation.create`, `.update`, `.delete`), `error`, `statusCode`, `dropped`.

```dart
client.syncFailures.listen((failure) {
  if (failure.dropped) {
    showMessage('${failure.recordId} was deleted on the server. Your edit was dropped.');
  } else {
    showMessage('The server rejected ${failure.operation.name} '
        'of ${failure.collection}/${failure.recordId} (${failure.statusCode}).');
  }
});

// User fixed the cause (for example a permission): retry parked changes too.
await client.syncPendingChanges(includeFailed: true);
// Or one collection: client.collection('posts').retryLocal(includeFailed: true)

// User gives up: remove the local change. The next read loads the server version.
await client.discardPendingChange('posts', recordId);
```

`discardPendingChange` removes the cached row only if it is pending.

## Waiting for Sync Completion

`client.syncCompleted` completes when the running pass ends. It never throws. Completion does not mean that the queue is empty: parked changes, and changes left when the server became unreachable, stay pending.

```dart
// Wait for the running sync pass to complete
await client.syncCompleted;
print('Sync pass complete');

// Useful before important operations
await client.syncCompleted;
final freshData = await client.collection('posts').getFullList(
  requestPolicy: RequestPolicy.networkOnly,
);
```

## Pending Records Query

Query records that are pending sync:

```dart
// Get all pending (unsynced) records in a collection, oldest first
final pendingPosts = await client.collection('posts').pending().get();

for (final post in pendingPosts) {
  final data = post.data;

  if (data[RecordMeta.syncError] != null) {
    print('Parked: ${post.id}');
  } else if (RecordMeta.flag(data[RecordMeta.deleted])) {
    print('Pending delete: ${post.id}');
  } else if (RecordMeta.flag(data[RecordMeta.isNew])) {
    print('Pending create: ${post.get<String>('title')}');
  } else {
    print('Pending update: ${post.get<String>('title')}');
  }
}
```

Watch the queue of all collections with `client.db.pendingRecords()`. It returns a Drift `Selectable<Service>`. It excludes local-only rows and rows of other accounts. It includes parked rows. Pass `service:` to limit it to one collection.

```dart
// Live pending-changes count for a badge
final pendingCount = client.db.pendingRecords().watch().map((rows) => rows.length);

// Parked rows only
final parked = client.db.pendingRecords().watch().map(
      (rows) => rows.where((r) => r.data[RecordMeta.syncError] != null).toList(),
    );
```

## UI Sync Indicators

Show users when data is pending sync:

```dart
class PostCard extends StatelessWidget {
  const PostCard({super.key, required this.post});
  final RecordModel post;

  @override
  Widget build(BuildContext context) {
    // Rows from watchRecords/watchRecord are cached rows with metadata.
    final pending = RecordMeta.isPending(post.data);
    final failed = post.data[RecordMeta.syncError] != null;
    
    return Card(
      child: ListTile(
        title: Text(post.get<String>('title') ?? ''),
        subtitle: Text(post.get<String>('content') ?? ''),
        trailing: failed
            ? const Icon(Icons.error_outline, color: Colors.red)
            : pending
                ? const Icon(Icons.cloud_upload, color: Colors.orange)
                : null,
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

Each client owns a realtime connectivity monitor tuned for PocketBase. It combines three signals: OS interface events (instant triggers), server health probes (`/api/health`) with exponential backoff while offline, and actual request outcomes. When the server becomes reachable again, the client starts `syncPendingChanges()` and live queries refetch. No app code is needed.

What counts as a failure:
- Only connectivity failures count: status 0, timeouts, socket errors, 502, 503, 504. Two consecutive failures mark the server as offline.
- Any server answer marks the server as reachable. This includes 4xx and 500.

```dart
// Last known server status
final isConnected = client.connectivity.isConnected;

// Interface up and server not known to be down.
// Offline-first policies skip the network when this is false.
final canReach = client.connectivity.canReachServer;

// A network interface is available.
// Strict policies (networkOnly, networkFirst) try the server when this is true.
final canTry = client.connectivity.shouldAttemptNetwork;

// Probe the server now, or soon (only while marked offline)
await client.connectivity.checkConnectivity();
client.connectivity.probeSoon();

// Stream of connectivity changes.
// Each new listener first gets the current status once, then only changes.
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

Offline deletes write a local tombstone (`deleted: true`) that stays invisible to all reads (`getFullList`, `getOne`, `watchRecords`, `search`, `$count`) until the sync engine confirms the server deletion. A record created offline and deleted before it syncs is removed locally at once. No server delete is queued. Raw database access can opt back in:

```dart
// Include tombstones (diagnostics, pending queue views)
await client.db.$query('posts', includeDeleted: true).get();
```

## Conflict Handling

pocketbase_drift merges conflicts per field:
- An offline update sends only the changed fields (`pendingFields`). The local value wins for those fields. Server changes to other fields stay.
- Until the change syncs, list refreshes and realtime events do not overwrite the locally changed fields.
- A realtime delete keeps a row with pending edits. The sync then gets 404, drops the local edit and emits `SyncFailure(dropped: true)` on `client.syncFailures`.

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
// 2. If a network interface is up, syncPendingChanges() runs

// No manual handling needed, but you can observe:
@override
void didChangeAppLifecycleState(AppLifecycleState state) {
  if (state == AppLifecycleState.resumed) {
    // Client automatically checks for pending syncs
  }
}
```

## Logout and Pending Changes

`authStore.clear()` (with `clearOnLogout: true`, the default) deletes the cache but keeps unsynced changes and their file blobs. Each pending row belongs to the account that wrote it (`pendingOwner`). Other accounts do not see these rows in reads, search or sync. They sync when the same account logs in again.

```dart
// Keeps this account's pending changes
client.authStore.clear();

// Deletes everything except the schema, including pending changes
await client.db.clearAllData();
```

Warn the user before logout when changes are pending:

```dart
final pending = await client.db.pendingRecords().get();
if (pending.isNotEmpty) {
  // Ask: "N changes are not synced. They will sync when you log in again."
}
```

## Best Practices

### Don't Retry Manually Unless Necessary

```dart
// ✅ Let automatic sync handle unreachable servers
await client.collection('posts').create(body: data);

// ✅ Catch server rejections: they are not queued or retried
try {
  await client.collection('posts').create(body: data);
} on ClientException catch (e) {
  // cacheAndNetwork throws only for a final server answer (4xx, for example 400 or 403).
  // Nothing was stored. Show the error to the user.
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
// Live pending-changes count across all collections
StreamBuilder<List<Service>>(
  stream: client.db.pendingRecords().watch(),
  builder: (context, snapshot) {
    final count = snapshot.data?.length ?? 0;
    if (count == 0) return const SizedBox.shrink();
    return Badge(
      label: Text('$count'),
      child: const Icon(Icons.cloud_upload),
    );
  },
);
```
