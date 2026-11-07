import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/fetching_indicator.dart';
import '../../../shared/widgets/offline_banner.dart';
import '../providers/task_providers.dart';
import '../widgets/task_edit_sheet.dart';

class TaskDetailScreen extends ConsumerWidget {
  const TaskDetailScreen({super.key, required this.taskId});

  final String taskId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final taskStateAsync = ref.watch(singleTaskStateProvider(taskId));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Task Details'),
        actions: [
          taskStateAsync.whenOrNull(
                data: (state) {
                  final task = state.data;
                  if (task == null) return null;
                  return IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    tooltip: 'Edit Task',
                    onPressed: () => TaskEditSheet.show(context, task: task),
                  );
                },
              ) ??
              const SizedBox.shrink(),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            tooltip: 'Delete Task',
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Delete Task?'),
                  content:
                      const Text('Are you sure you want to delete this task?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      style:
                          FilledButton.styleFrom(backgroundColor: Colors.red),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                await ref.read(taskRepositoryProvider).deleteTask(taskId);
                if (context.mounted) context.pop();
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          const OfflineBanner(),
          taskStateAsync.when(
            data: (state) => FetchingIndicator(
              isFetching: state.isFetchingNetwork,
              hasError: state.hasError,
            ),
            loading: () => const FetchingIndicator(isFetching: true),
            error: (err, st) =>
                const FetchingIndicator(isFetching: false, hasError: true),
          ),
          Expanded(
            child: taskStateAsync.when(
              data: (state) {
                final task = state.data;
                if (task == null) {
                  return const Center(child: Text('Task not found.'));
                }

                return SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Completion Header
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Checkbox(
                                value: task.isCompleted,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                onChanged: (_) async {
                                  await ref
                                      .read(taskRepositoryProvider)
                                      .toggleTask(task.id, task.isCompleted);
                                },
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  task.title,
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    decoration: task.isCompleted
                                        ? TextDecoration.lineThrough
                                        : null,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Meta details card
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'METADATA & RELATIONS',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const Divider(height: 24),
                              _buildMetaRow(
                                context,
                                label: 'Priority',
                                value: task.priority.name.toUpperCase(),
                                icon: Icons.flag_outlined,
                              ),
                              const SizedBox(height: 12),
                              _buildMetaRow(
                                context,
                                label: 'Project Relation',
                                value: task.project?.name ??
                                    (task.projectId?.isNotEmpty == true
                                        ? 'ID: ${task.projectId}'
                                        : 'None'),
                                icon: Icons.folder_outlined,
                                subtitle: task.project != null
                                    ? 'Locally expanded from "projects" collection'
                                    : null,
                              ),
                              if (task.dueDate != null &&
                                  task.dueDate!.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                _buildMetaRow(
                                  context,
                                  label: 'Due Date',
                                  value: task.dueDate!,
                                  icon: Icons.calendar_today_outlined,
                                ),
                              ],
                              if (task.tags.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                _buildMetaRow(
                                  context,
                                  label: 'Tags',
                                  value: task.tags,
                                  icon: Icons.tag,
                                ),
                              ],
                              const Divider(height: 24),
                              _buildMetaRow(
                                context,
                                label: 'Record ID',
                                value: task.id,
                                icon: Icons.fingerprint,
                              ),
                              if (task.created != null) ...[
                                const SizedBox(height: 12),
                                _buildMetaRow(
                                  context,
                                  label: 'Created',
                                  value: task.created!,
                                  icon: Icons.access_time,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      if (task.description.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'DESCRIPTION',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.primary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  task.description,
                                  style: theme.textTheme.bodyMedium,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => ErrorView(
                message: err.toString(),
                onRetry: () => ref.invalidate(singleTaskStateProvider(taskId)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetaRow(
    BuildContext context, {
    required String label,
    required String value,
    required IconData icon,
    String? subtitle,
  }) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 10,
                    color: Colors.green.shade700,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
