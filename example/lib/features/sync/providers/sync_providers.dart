import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocketbase_drift/pocketbase_drift.dart';

import '../../../shared/providers/pocketbase_provider.dart';

class PendingRecordInfo {
  const PendingRecordInfo({
    required this.service,
    required this.id,
    required this.data,
    required this.isDeleted,
  });

  final String service;
  final String id;
  final Map<String, dynamic> data;
  final bool isDeleted;
}

/// Stream provider for records with unsynced local changes.
final pendingSyncItemsProvider =
    StreamProvider.autoDispose<List<PendingRecordInfo>>((ref) {
  final client = ref.watch(pocketBaseProvider);

  return client.db.pendingRecords().watch().map((rows) => [
        for (final row in rows)
          PendingRecordInfo(
            service: row.service,
            id: row.id,
            data: row.data,
            isDeleted: row.data['deleted'] == true,
          ),
      ]);
});

/// Count of pending items awaiting sync.
final pendingSyncCountProvider = Provider.autoDispose<int>((ref) {
  final items = ref.watch(pendingSyncItemsProvider).valueOrNull;
  return items?.length ?? 0;
});

/// Sync controller for triggering retry operations and cache clearing.
final syncControllerProvider = Provider<SyncController>((ref) {
  return SyncController(ref.watch(pocketBaseProvider));
});

class SyncController {
  SyncController(this._client);

  final $PocketBase _client;

  /// Pushes every pending local change to the server. Joins a sync that is
  /// already running instead of starting a second one.
  Future<void> syncNow() => _client.syncPendingChanges();

  /// Deletes all cached data, cached responses and files, including
  /// unsynced local changes. The cached schema is kept.
  Future<void> clearCache() => _client.db.clearCache(keepPending: false);
}
