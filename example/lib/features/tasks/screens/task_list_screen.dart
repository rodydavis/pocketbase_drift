import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/providers/pocketbase_provider.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/fetching_indicator.dart';
import '../../../shared/widgets/offline_banner.dart';
import '../../projects/providers/project_providers.dart';
import '../providers/task_providers.dart';
import '../widgets/policy_picker_sheet.dart';
import '../widgets/task_card.dart';
import '../widgets/task_edit_sheet.dart';

class TaskListScreen extends ConsumerWidget {
  const TaskListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasksStateAsync = ref.watch(tasksStateProvider);
    final currentPolicy = ref.watch(activeRequestPolicyProvider);
    final selectedProjectId = ref.watch(selectedProjectFilterProvider);
    final completionFilter = ref.watch(completionFilterProvider);
    final projects = ref.watch(projectsListProvider);

    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('TaskFlow'),
            Text(
              'Policy: ${currentPolicy.name}',
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'Change Request Policy',
            onPressed: () => PolicyPickerSheet.show(context),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Invalidate Stream',
            onPressed: () => ref.invalidate(tasksStateProvider),
          ),
        ],
      ),
      body: Column(
        children: [
          const OfflineBanner(),
          tasksStateAsync.when(
            data: (state) => FetchingIndicator(
              isFetching: state.isFetchingNetwork,
              hasError: state.hasError,
            ),
            loading: () => const FetchingIndicator(isFetching: true),
            error: (err, st) =>
                const FetchingIndicator(isFetching: false, hasError: true),
          ),
          // Filter bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  // Completion status filters
                  FilterChip(
                    label: const Text('All'),
                    selected: completionFilter == null,
                    onSelected: (_) => ref
                        .read(completionFilterProvider.notifier)
                        .state = null,
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    label: const Text('Active'),
                    selected: completionFilter == false,
                    onSelected: (_) => ref
                        .read(completionFilterProvider.notifier)
                        .state = false,
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    label: const Text('Completed'),
                    selected: completionFilter == true,
                    onSelected: (_) => ref
                        .read(completionFilterProvider.notifier)
                        .state = true,
                  ),
                  const SizedBox(width: 16),
                  // Project filter
                  if (projects.isNotEmpty) ...[
                    PopupMenuButton<String?>(
                      initialValue: selectedProjectId,
                      onSelected: (val) => ref
                          .read(selectedProjectFilterProvider.notifier)
                          .state = val,
                      child: Chip(
                        avatar: const Icon(Icons.folder, size: 16),
                        label: Text(
                          selectedProjectId == null
                              ? 'All Projects'
                              : projects
                                  .firstWhere(
                                    (p) => p.id == selectedProjectId,
                                    orElse: () => projects.first,
                                  )
                                  .name,
                        ),
                        deleteIcon: selectedProjectId != null
                            ? const Icon(Icons.close, size: 14)
                            : null,
                        onDeleted: selectedProjectId != null
                            ? () => ref
                                .read(selectedProjectFilterProvider.notifier)
                                .state = null
                            : null,
                      ),
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: null,
                          child: Text('All Projects'),
                        ),
                        ...projects.map(
                          (p) => PopupMenuItem(
                            value: p.id,
                            child: Text(p.name),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          Expanded(
            child: tasksStateAsync.when(
              data: (state) {
                final tasks = state.data;
                if (tasks.isEmpty) {
                  return EmptyState(
                    title: 'No Tasks Found',
                    message:
                        'Create a task to test offline-first caching, background sync, and Drift streams.',
                    icon: Icons.check_circle_outline,
                    actionLabel: 'Create Task',
                    onAction: () => TaskEditSheet.show(context),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: tasks.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final task = tasks[index];
                    return TaskCard(
                      task: task,
                      onTap: () => context.push('/tasks/${task.id}'),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => ErrorView(
                message: err.toString(),
                onRetry: () => ref.invalidate(tasksStateProvider),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => TaskEditSheet.show(context),
        icon: const Icon(Icons.add),
        label: const Text('New Task'),
      ),
    );
  }
}
