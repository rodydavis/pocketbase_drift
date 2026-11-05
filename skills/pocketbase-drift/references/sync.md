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
| `pendingBase` | map | Server value of each pending field when it first became pending (`{field: value}`) |
| `baseUpdated` | string | Server `updated` value of the row when its pending change started |
| `pendingDeltas` | map | Pending fields whose every local edit was a modifier, with the kind: a `DeltaKind` value (`DeltaKind.number`, `.append`, `.prepend`, `.remove`; the strings `number`, `append`, `prepend`, `remove`). Sync sends these fields as modifiers. |

Helpers: `RecordMeta.isPending(data)`, `RecordMeta.flag(value)` (reads `true`/`1`), `RecordMeta.strip(data)` (removes the bookkeeping keys). `DeltaKind` is exported.

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

Offline deletions are tombstones. Normal reads do not return them (see "Deleted Records"). A queued deletion of a record that was not cached is a bare tombstone: the id and the bookkeeping keys only, no record fields.

## Automatic Sync

`client.syncPendingChanges()` sends all pending changes. It runs automatically:
- When the client is created (startup)
- When the server becomes reachable again (`connectivity.statusStream` emits `true`)
- When the app resumes from background (and a network interface is up)
- After login (the auth record id changes to a new non-null value)

Rules of a sync pass:
- **Single-flight:** Only one pass runs at a time. A call during a pass returns a future that completes after one more pass. Changes queued during the pass are included.
- **Order:** Collections sync parents first (by relation fields). Records sync oldest first (by `cachedAt`).
- **Updates are partial:** An update sends only the fields in `pendingFields`. Changes made on other devices to other fields stay on the server. A field changed only with `+`/`-` modifiers is sent as a modifier (see "Conflict Handling").
- **Creates send the whole record.** If an earlier attempt created the record and the response was lost (id already exists), the create becomes an update.
- **Files are sent once:** New files go as multipart parts with the create or update. Later edits do not upload them again.
- **Sent fields are done:** a field that a push or a batch sent is not sent again when the server stores it in another form (dates) or does not return it (the `password` of an auth record). With a `fields:` projection (`pushPending(id, query: {'fields': ...})`, or a batch update with `fields`), the cached record keeps its other fields and queued increments are not lost.
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

Pushes, online writes and batch sends of one record run one at a time. A second `pushPending` call waits for the running push and then sends what is still pending. Changes made while a push is in flight stay pending: an edit keeps the server's names of the files just uploaded, a file attached meanwhile is still uploaded, a delete stays a queued deletion (also for a record whose create is being pushed), and a `cacheOnly` change stays local. An online update removes the fields it set from a queued edit of the same record; an online modifier (`n+: 1`) of a field with a queued modifier edit keeps both changes. An online write waits at most `requestTimeout` for a running push, so it reaches the server last; after that, `cacheAndNetwork` queues it behind the push and `networkOnly`/`networkFirst` throw `ClientException` with status 0.

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

A pending deletion can be a bare row (a record that was not cached when it was deleted): only `id` and the bookkeeping keys. Show the id for deletions; do not read record fields.

Watch the queue of all collections with `client.db.pendingRecords()`. It returns a Drift `Selectable<Service>`. It excludes local-only rows and rows of other accounts. It includes parked rows. Pass `service:` to limit it to one collection. An open `.watch()` follows an account switch: after a login it shows the rows of the new account without a new listen. It re-runs on every write to the `services` table, of any collection.

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

Offline deletes write a local tombstone (`deleted: true`) that stays invisible to all reads (`getFullList`, `getOne`, `watchRecords`, `search`, `$count`) until the sync engine confirms the server deletion. A record created offline and deleted before it syncs is removed locally at once. No server delete is queued.

A delete of a record that is not cached is queued too: with `cacheAndNetwork` when the server is unreachable (offline, 503, connection refused, timeout), with `cacheFirst` always. The tombstone is a bare row: `id`, `deleted: true`, `synced: false`, `isNew: false`, `noSync: false`, `pendingRev` and `pendingOwner`. An offline batch delete of such an id returns status 204. When the server answers 404 at sync time (already deleted, or the delete rule does not match), the deletion ends without a `SyncFailure`, like any tombstone.

`writeLocalDelete(id, sync: true)` (on `$RecordService`; `client.db.writeLocalDelete(service, id, sync: true)`) always returns `true`. It returns `false` only for `sync: false` when the record is not cached.

Raw database access can opt back in:

```dart
// Include tombstones (diagnostics, pending queue views)
await client.db.$query('posts', includeDeleted: true).get();
```

## Conflict Handling

pocketbase_drift merges a queued update with the server per field:
- An offline update sends only the changed fields (`pendingFields`). Server changes to other fields stay.
- **Modifier edits merge.** When every local edit of a field was a modifier (`n+`/`n-` for numbers; `f+`, `+f`, `f-` for multi-value relation, select and file fields), sync sends the change from `pendingBase` as modifiers: numbers send their difference (`n+: 2`; a negative difference as `n-`), multi-value fields send the added values as `f+` (`+f` for prepends) and the removed values as `f-`. Increments, appends, removals and file uploads of other devices stay. The field must be in the cached collection schema.
- **Plain sets are last-write-wins.** A field with a plain set (`n: 5`, `tags: [...]`) anywhere in its pending history sends its absolute value. Single-value relation, select and file fields, JSON fields and text fields always send their absolute value. Pending rows written before 0.7.0 (no `pendingBase`) send absolute values.
- **Online writes:** an online update removes the fields it set from the queued edit. An online modifier (`n+: 1` with `networkFirst` or `cacheAndNetwork`) of a field with a queued modifier edit keeps both. An online plain set supersedes the queued edit of that field.
- **Batches:** a batch update does not mark the queued change as synced. Fields, increments and uploads that the batch did not send still sync. A value that the batch set is not overwritten later by the older queued value (also with `networkOnly`). An edit made while an online batch is in flight stays pending, also when it restores the old value.
- Until the change syncs, list refreshes and realtime events do not overwrite the locally changed fields.
- A realtime delete keeps a row with pending edits. The sync then gets 404, drops the local edit and emits `SyncFailure(dropped: true)` on `client.syncFailures`.
- Limits: mixed append and prepend edits are sent as an append. Float differences can have rounding errors.

For counters, use `+`/`-` modifiers. They work offline and merge with other devices:

```dart
// Two devices like the post offline; after sync the server has both likes.
await client.collection('posts').update(
  postId,
  body: {'likes+': 1},
  requestPolicy: RequestPolicy.cacheFirst,
);
```

For data that needs server confirmation before the UI continues (orders, payments), use `networkFirst`:

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
