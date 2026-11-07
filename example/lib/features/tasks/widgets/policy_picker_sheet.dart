import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocketbase_drift/pocketbase_drift.dart';

import '../../../shared/providers/pocketbase_provider.dart';

class PolicyPickerSheet extends ConsumerWidget {
  const PolicyPickerSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const PolicyPickerSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentPolicy = ref.watch(activeRequestPolicyProvider);

    final policies = [
      (
        RequestPolicy.cacheAndNetwork,
        'Cache and Network (Recommended)',
        'Renders cached local SQLite data instantly, fetches updates in the background, and emits again.',
        Icons.cached,
      ),
      (
        RequestPolicy.cacheFirst,
        'Cache First (Fastest)',
        'Serves local cache immediately. Only makes remote network requests if local cache is empty.',
        Icons.bolt,
      ),
      (
        RequestPolicy.networkFirst,
        'Network First (Freshest)',
        'Attempts network request first for live server state. Falls back to local SQLite cache if offline.',
        Icons.cloud_sync,
      ),
      (
        RequestPolicy.cacheOnly,
        'Cache Only (Offline-Only)',
        'Reads exclusively from local SQLite. Completely bypasses network regardless of connectivity.',
        Icons.save_alt,
      ),
      (
        RequestPolicy.networkOnly,
        'Network Only (Strict)',
        'Bypasses local database. Throws error if offline or server is unavailable.',
        Icons.cloud,
      ),
    ];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.tune, color: Colors.indigo),
                const SizedBox(width: 8),
                Text(
                  'Select Request Policy',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'PocketBase Drift supports 5 caching policies to balance offline speed and data freshness.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey.shade600,
                  ),
            ),
            const SizedBox(height: 16),
            ...policies.map((p) {
              final isSelected = currentPolicy == p.$1;
              return Card(
                elevation: isSelected ? 1 : 0,
                color: isSelected
                    ? Theme.of(context)
                        .colorScheme
                        .primaryContainer
                        .withValues(alpha: 0.4)
                    : null,
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: ListTile(
                  leading: Icon(
                    p.$4,
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : Colors.grey,
                  ),
                  title: Text(
                    p.$2,
                    style: TextStyle(
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  subtitle: Text(
                    p.$3,
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: isSelected
                      ? Icon(Icons.check_circle,
                          color: Theme.of(context).colorScheme.primary)
                      : null,
                  onTap: () {
                    ref
                        .read(activeRequestPolicyProvider.notifier)
                        .setPolicy(p.$1);
                    Navigator.of(context).pop();
                  },
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
