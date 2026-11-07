import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/fetching_indicator.dart';
import '../../../shared/widgets/offline_banner.dart';
import '../providers/project_providers.dart';
import '../widgets/project_edit_dialog.dart';

class ProjectListScreen extends ConsumerWidget {
  const ProjectListScreen({super.key});

  Color _parseColor(String hex) {
    try {
      final clean = hex.replaceAll('#', '');
      return Color(int.parse('FF$clean', radix: 16));
    } catch (_) {
      return Colors.indigo;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stateAsync = ref.watch(projectsStateProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Projects'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            tooltip: 'New Project',
            onPressed: () => ProjectEditDialog.show(context),
          ),
        ],
      ),
      body: Column(
        children: [
          const OfflineBanner(),
          stateAsync.when(
            data: (state) => FetchingIndicator(
              isFetching: state.isFetchingNetwork,
              hasError: state.hasError,
            ),
            loading: () => const FetchingIndicator(isFetching: true),
            error: (err, st) =>
                const FetchingIndicator(isFetching: false, hasError: true),
          ),
          Expanded(
            child: stateAsync.when(
              data: (state) {
                final projects = state.data;
                if (projects.isEmpty) {
                  return EmptyState(
                    title: 'No Projects Found',
                    message:
                        'Projects help organize tasks and demonstrate SQLite relations in pocketbase_drift.',
                    icon: Icons.folder_outlined,
                    actionLabel: 'Create Project',
                    onAction: () => ProjectEditDialog.show(context),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: projects.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final project = projects[index];
                    final color = _parseColor(project.color);

                    return Card(
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        leading: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.folder, color: color),
                        ),
                        title: Text(
                          project.name,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: project.description.isNotEmpty
                            ? Text(
                                project.description,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              )
                            : null,
                        trailing: PopupMenuButton<String>(
                          onSelected: (value) async {
                            if (value == 'edit') {
                              ProjectEditDialog.show(context, project: project);
                            } else if (value == 'delete') {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('Delete Project?'),
                                  content: Text(
                                      'Are you sure you want to delete "${project.name}"?'),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.of(ctx).pop(false),
                                      child: const Text('Cancel'),
                                    ),
                                    FilledButton(
                                      onPressed: () =>
                                          Navigator.of(ctx).pop(true),
                                      style: FilledButton.styleFrom(
                                        backgroundColor: Colors.red,
                                      ),
                                      child: const Text('Delete'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirm == true) {
                                await ref
                                    .read(projectRepositoryProvider)
                                    .deleteProject(project.id);
                              }
                            }
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(
                              value: 'edit',
                              child: Row(
                                children: [
                                  Icon(Icons.edit, size: 18),
                                  SizedBox(width: 8),
                                  Text('Edit'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Row(
                                children: [
                                  Icon(Icons.delete,
                                      size: 18, color: Colors.red),
                                  SizedBox(width: 8),
                                  Text('Delete',
                                      style: TextStyle(color: Colors.red)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => ErrorView(
                message: err.toString(),
                onRetry: () => ref.invalidate(projectsStateProvider),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
