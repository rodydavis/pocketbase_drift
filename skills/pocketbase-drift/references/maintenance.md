# Maintenance

This guide covers cache cleanup, TTL configuration, and database maintenance.

## Cache TTL

By default, cached data expires 60 days after it was cached. The age of a row is the time it was last written to the cache (`cachedAt`), not the server's `updated` value. Configure on initialization:

```dart
final client = $PocketBase.database(
  'https://example.pocketbase.io',
  cacheTtl: Duration(days: 30), // Custom TTL
);
```

## Running Maintenance

Call `runMaintenance()` to clean up expired data:

```dart
// Run with configured TTL
final result = await client.runMaintenance();
print('Cleaned up ${result.totalDeleted} expired items');

// Run with one-time custom TTL
await client.runMaintenance(ttl: Duration(days: 7));
```

## MaintenanceResult

The result provides counts of what was cleaned:

```dart
final result = await client.runMaintenance();

print('Deleted records: ${result.deletedRecords}');
print('Deleted responses: ${result.deletedResponses}');
print('Deleted files: ${result.deletedFiles}');
print('Total deleted: ${result.totalDeleted}');
```

| Property | Description |
|----------|-------------|
| `deletedRecords` | Expired synced records removed |
| `deletedResponses` | Expired cached API responses removed |
| `deletedFiles` | Expired file blobs and blobs of records no longer cached |
| `totalDeleted` | Sum of all deletions |

## What Gets Cleaned

Maintenance **ONLY** deletes:
- Synced records cached before the cutoff (`cachedAt` < now − TTL). This includes rows fetched by list reads.
- Cached API responses older than TTL
- File blobs past their expiration
- Orphaned file blobs: blobs created before the cutoff whose record is no longer cached

Maintenance **NEVER** deletes:
- Unsynced local changes (`synced: false`), including changes parked with `syncError`
- Local-only records (`noSync: true`)
- Pending deletions (`deleted: true, synced: false`)
- The schema

**You will never lose unsynced data during maintenance.**

## When to Run Maintenance

### On App Startup

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final client = $PocketBase.database('https://example.com');
  
  // Run maintenance in background after app starts
  Future.microtask(() async {
    final result = await client.runMaintenance();
    if (result.totalDeleted > 0) {
      Logger.info('Cleaned ${result.totalDeleted} expired cache items');
    }
  });

  runApp(MyApp(client: client));
}
```

### Periodically

```dart
// Run weekly or when user triggers
class SettingsScreen extends ConsumerWidget {
  Future<void> _clearOldCache(WidgetRef ref) async {
    final client = ref.read(pocketbaseProvider);
    final result = await client.runMaintenance(ttl: Duration(days: 7));
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Cleaned ${result.totalDeleted} items')),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      children: [
        ListTile(
          title: const Text('Clear Old Cache'),
          subtitle: const Text('Remove data older than 7 days'),
          trailing: const Icon(Icons.cleaning_services),
          onTap: () => _clearOldCache(ref),
        ),
      ],
    );
  }
}
```

## Manual Cache Clearing

### Clear the Cache

```dart
// Delete cached server data, cached responses and file blobs.
// Unsynced changes and their blobs stay (default keepPending: true).
await client.db.clearCache();
```

Logout (`authStore.clear()` with `clearOnLogout`, the default) calls `clearCache(keepPending: true)`. Pending changes belong to the account that wrote them (`pendingOwner`). Other accounts do not see them. They sync when that account logs in again.

`clearCache` also deletes local-only rows (`noSync`).

### Clear All Data

```dart
// Delete everything except the schema (use with caution!)
await client.db.clearAllData();
```

**Warning**: This deletes ALL cached data including unsynced changes. It is the same as `clearCache(keepPending: false)`.

### Clear Specific Collection

```dart
// Delete all cached records in a collection
await client.db.customStatement(
  "DELETE FROM services WHERE service = ?",
  ['temp_data'],
);
```

**Warning**: This statement also deletes unsynced changes of the collection.

### Clear Old Records Manually

```dart
import 'package:drift/drift.dart';

// Delete synced posts cached more than 30 days ago
final cutoff = DateTime.now().subtract(const Duration(days: 30));

await client.db.customUpdate(
  "DELETE FROM services WHERE service = 'posts' "
  'AND cachedAt < ? '
  "AND COALESCE(json_extract(data, '\$.synced'), 1) = 1 "
  "AND COALESCE(json_extract(data, '\$.noSync'), 0) = 0",
  variables: [Variable<DateTime>(cutoff)],
  updates: {client.db.services},
  updateKind: UpdateKind.delete,
);
```

## Database Size

Check cache size:

```dart
// Count records per collection
final counts = await client.db.customSelect('''
  SELECT service, COUNT(*) as count
  FROM services
  GROUP BY service
''').get();

for (final row in counts) {
  print('${row.read<String>('service')}: ${row.read<int>('count')} records');
}

// Count file blobs
final fileCount = await client.db.customSelect(
  "SELECT COUNT(*) as count FROM BlobFiles",
).getSingle();
print('Cached files: ${fileCount.read<int>('count')}');
```

## Cache Strategies by Data Type

### Frequently Updated Data

Use shorter TTL or more aggressive maintenance:

```dart
// Clear feed items weekly
await client.runMaintenance(ttl: Duration(days: 7));
```

### Critical Data

Keep longer, ensure synced before cleaning:

```dart
// Ensure sync is complete before maintenance
await client.syncCompleted;
await client.runMaintenance();
```

### Large Files

Monitor file cache specifically:

```dart
// Clear files downloaded more than 30 days ago.
// Keep the blobs of unsynced changes: sync uploads them.
final cutoff =
    DateTime.now().toUtc().subtract(const Duration(days: 30)).toIso8601String();

await client.db.customStatement('''
  DELETE FROM BlobFiles
  WHERE created < ?
    AND recordId NOT IN (
      SELECT id FROM services
      WHERE COALESCE(json_extract(data, '\$.synced'), 1) = 0
    )
''', [cutoff]);
```

## Riverpod Provider for Maintenance

```dart
// Maintenance provider
final maintenanceResultProvider = FutureProvider<MaintenanceResult?>((ref) async {
  final client = ref.watch(pocketbaseProvider);
  
  // Only run once per app session
  final ran = ref.state.valueOrNull != null;
  if (ran) return ref.state.valueOrNull;
  
  return client.runMaintenance();
});

// Use in startup widget
class AppStartup extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Trigger maintenance on startup
    ref.watch(maintenanceResultProvider);
    
    return const MyApp();
  }
}
```

## Best Practices

1. **Run maintenance on startup** - Clean old data when app launches
2. **Don't run too frequently** - Once per session is usually enough
3. **Use appropriate TTL** - Balance between freshness and storage
4. **Monitor cache growth** - For apps with lots of data, track size over time
5. **Inform users** - Let users manually clear cache if needed
6. **Ensure sync first** - For critical cleanup, wait for sync completion
