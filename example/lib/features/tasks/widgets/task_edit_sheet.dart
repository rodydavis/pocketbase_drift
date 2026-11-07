import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../projects/providers/project_providers.dart';
import '../models/task_model.dart';
import '../providers/task_providers.dart';

class TaskEditSheet extends ConsumerStatefulWidget {
  const TaskEditSheet({super.key, this.task});

  final TaskModel? task;

  static Future<void> show(BuildContext context, {TaskModel? task}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => TaskEditSheet(task: task),
    );
  }

  @override
  ConsumerState<TaskEditSheet> createState() => _TaskEditSheetState();
}

class _TaskEditSheetState extends ConsumerState<TaskEditSheet> {
  late final TextEditingController _titleController;
  late final TextEditingController _descController;
  late final TextEditingController _tagsController;
  TaskPriority _priority = TaskPriority.medium;
  String? _selectedProjectId;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.task?.title ?? '');
    _descController =
        TextEditingController(text: widget.task?.description ?? '');
    _tagsController = TextEditingController(text: widget.task?.tags ?? '');
    _priority = widget.task?.priority ?? TaskPriority.medium;
    _selectedProjectId = widget.task?.projectId;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      final repo = ref.read(taskRepositoryProvider);
      if (widget.task == null) {
        await repo.createTask(
          title: title,
          description: _descController.text.trim(),
          priority: _priority,
          projectId: _selectedProjectId,
          tags: _tagsController.text.trim(),
        );
      } else {
        await repo.updateTask(
          widget.task!.id,
          title: title,
          description: _descController.text.trim(),
          priority: _priority,
          projectId: _selectedProjectId,
          tags: _tagsController.text.trim(),
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving task: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final projects = ref.watch(projectsListProvider);
    final isEditing = widget.task != null;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 20,
        right: 20,
        top: 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isEditing ? 'Edit Task' : 'New Task',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Task Title',
                hintText: 'e.g. Implement offline database sync',
              ),
              autofocus: true,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _descController,
              decoration: const InputDecoration(
                labelText: 'Description (Optional)',
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            // Project selection (Relation)
            DropdownButtonFormField<String>(
              initialValue: _selectedProjectId,
              decoration: const InputDecoration(
                labelText: 'Assign to Project (Relation)',
                prefixIcon: Icon(Icons.folder_outlined),
              ),
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('No Project (Standalone)'),
                ),
                ...projects.map(
                  (p) => DropdownMenuItem(
                    value: p.id,
                    child: Text(p.name),
                  ),
                ),
              ],
              onChanged: (val) => setState(() => _selectedProjectId = val),
            ),
            const SizedBox(height: 16),
            // Priority selection
            const Text('Priority:'),
            const SizedBox(height: 8),
            SegmentedButton<TaskPriority>(
              segments: const [
                ButtonSegment(value: TaskPriority.low, label: Text('Low')),
                ButtonSegment(value: TaskPriority.medium, label: Text('Med')),
                ButtonSegment(value: TaskPriority.high, label: Text('High')),
                ButtonSegment(
                    value: TaskPriority.urgent, label: Text('Urgent')),
              ],
              selected: {_priority},
              onSelectionChanged: (set) =>
                  setState(() => _priority = set.first),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _tagsController,
              decoration: const InputDecoration(
                labelText: 'Tags (Optional)',
                hintText: 'e.g. flutter, drift, offline',
                prefixIcon: Icon(Icons.tag),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: _isLoading ? null : _save,
                child: _isLoading
                    ? const CircularProgressIndicator(strokeWidth: 2)
                    : Text(isEditing ? 'Save Changes' : 'Create Task'),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
