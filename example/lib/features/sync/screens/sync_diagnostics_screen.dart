import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/pocketbase_provider.dart';
import '../../../shared/widgets/offline_banner.dart';
import '../../tasks/widgets/policy_picker_sheet.dart';
import '../providers/sync_providers.dart';

class SyncDiagnosticsScreen extends ConsumerStatefulWidget {
  const SyncDiagnosticsScreen({super.key});

  @override
  ConsumerState<SyncDiagnosticsScreen> createState() =>
      _SyncDiagnosticsScreenState();
}

class _SyncDiagnosticsScreenState extends ConsumerState<SyncDiagnosticsScreen> {
  bool _isSyncing = false;

  Future<void> _triggerSync() async {
    setState(() => _isSyncing = true);
    try {
      await ref.read(syncControllerProvider).syncNow();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sync completed successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sync failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isOnline = ref.watch(connectivityStatusProvider).valueOrNull ?? true;
    final activePolicy = ref.watch(activeRequestPolicyProvider);
    final pendingItemsAsync = ref.watch(pendingSyncItemsProvider);
    final pendingCount = ref.watch(pendingSyncCountProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sync Diagnostics'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: 'Clear SQLite Cache',
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Clear SQLite Cache?'),
                  content: const Text(
                    'This will erase local SQLite cache tables. You will need to refresh from server or re-seed.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      style:
                          FilledButton.styleFrom(backgroundColor: Colors.red),
                      child: const Text('Clear All'),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                await ref.read(syncControllerProvider).clearCache();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Local cache cleared.')),
                  );
                }
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          const OfflineBanner(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Diagnostics overview card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SYSTEM STATUS',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Divider(height: 24),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            isOnline ? Icons.wifi : Icons.wifi_off,
                            color: isOnline ? Colors.green : Colors.red,
                          ),
                          title: const Text('Internet Access'),
                          subtitle: Text(
                            isOnline
                                ? 'Connected to Internet'
                                : 'Offline / Disconnected',
                          ),
                        ),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.tune, color: Colors.indigo),
                          title: const Text('Active Request Policy'),
                          subtitle: Text(activePolicy.name),
                          trailing: TextButton(
                            onPressed: () => PolicyPickerSheet.show(context),
                            child: const Text('Change'),
                          ),
                        ),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading:
                              const Icon(Icons.storage, color: Colors.blueGrey),
                          title: const Text('Database Engine'),
                          subtitle: const Text(
                            'Drift SQLite with Schema Caching & FTS5',
                          ),
                        ),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            pendingCount > 0
                                ? Icons.cloud_upload_outlined
                                : Icons.cloud_done_outlined,
                            color: pendingCount > 0
                                ? Colors.amber.shade800
                                : Colors.green,
                          ),
                          title: const Text('Pending Sync Queue'),
                          subtitle: Text(
                            '$pendingCount local mutation(s) awaiting server sync',
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _isSyncing ? null : _triggerSync,
                            icon: _isSyncing
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white),
                                  )
                                : const Icon(Icons.sync),
                            label: const Text('Sync Now'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                // Pending Queue Section Header
                Row(
                  children: [
                    Text(
                      'Pending Queue',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: pendingCount > 0
                            ? Colors.amber.shade800
                            : Colors.grey.shade400,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$pendingCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                pendingItemsAsync.when(
                  data: (items) {
                    if (items.isEmpty) {
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: Column(
                            children: [
                              const Icon(Icons.cloud_done,
                                  size: 40, color: Colors.green),
                              const SizedBox(height: 8),
                              Text(
                                'Sync Queue Empty',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'All local modifications are currently synced with server.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    return Column(
                      children: items.map((item) {
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ExpansionTile(
                            leading: Icon(
                              item.isDeleted
                                  ? Icons.delete_outline
                                  : Icons.edit_note,
                              color: item.isDeleted
                                  ? Colors.red
                                  : Colors.amber.shade800,
                            ),
                            title: Text(
                              '${item.service} / ${item.id}',
                              style: const TextStyle(
                                  fontFamily: 'monospace', fontSize: 13),
                            ),
                            subtitle: Text(
                              item.isDeleted
                                  ? 'Pending Deletion'
                                  : 'Pending Server Write',
                              style: TextStyle(
                                fontSize: 11,
                                color: item.isDeleted
                                    ? Colors.red
                                    : Colors.amber.shade800,
                              ),
                            ),
                            children: [
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                color: theme.colorScheme.surfaceContainerHighest
                                    .withValues(alpha: 0.5),
                                child: Text(
                                  const JsonEncoder.withIndent('  ')
                                      .convert(item.data),
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    );
                  },
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Text('Error loading queue: $e'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
