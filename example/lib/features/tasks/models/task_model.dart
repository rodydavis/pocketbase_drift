import 'package:pocketbase_drift/pocketbase_drift.dart';

import '../../projects/models/project_model.dart';

enum TaskPriority {
  low,
  medium,
  high,
  urgent;

  static TaskPriority fromString(String? val) {
    return TaskPriority.values.firstWhere(
      (e) => e.name == (val ?? '').toLowerCase(),
      orElse: () => TaskPriority.medium,
    );
  }
}

/// Typed domain model representing a Task with relation expansion support.
class TaskModel {
  const TaskModel({
    required this.id,
    required this.title,
    this.description = '',
    this.isCompleted = false,
    this.priority = TaskPriority.medium,
    this.dueDate,
    this.projectId,
    this.project,
    this.tags = '',
    this.created,
    this.updated,
  });

  final String id;
  final String title;
  final String description;
  final bool isCompleted;
  final TaskPriority priority;
  final String? dueDate;
  final String? projectId;
  final ProjectModel? project;
  final String tags;
  final String? created;
  final String? updated;

  factory TaskModel.fromRecord(RecordModel record) {
    // Extract expanded project relation if present
    ProjectModel? expandedProject;
    final expandedData = record.data['expand'];
    if (expandedData is Map && expandedData['project'] != null) {
      final projRaw = expandedData['project'];
      if (projRaw is Map<String, dynamic>) {
        expandedProject = ProjectModel(
          id: projRaw['id'] as String? ?? '',
          name: projRaw['name'] as String? ?? '',
          description: projRaw['description'] as String? ?? '',
          color: projRaw['color'] as String? ?? '#6366F1',
        );
      }
    }

    return TaskModel(
      id: record.id,
      title: record.getStringValue('title'),
      description: record.getStringValue('description'),
      isCompleted: record.getBoolValue('is_completed'),
      priority: TaskPriority.fromString(record.getStringValue('priority')),
      dueDate: record.getStringValue('due_date'),
      projectId: record.getStringValue('project'),
      project: expandedProject,
      tags: record.getStringValue('tags'),
      created: record.getStringValue('created'),
      updated: record.getStringValue('updated'),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'description': description,
      'is_completed': isCompleted,
      'priority': priority.name,
      'due_date': dueDate,
      'project': projectId,
      'tags': tags,
    };
  }

  TaskModel copyWith({
    String? id,
    String? title,
    String? description,
    bool? isCompleted,
    TaskPriority? priority,
    String? dueDate,
    String? projectId,
    ProjectModel? project,
    String? tags,
  }) {
    return TaskModel(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      isCompleted: isCompleted ?? this.isCompleted,
      priority: priority ?? this.priority,
      dueDate: dueDate ?? this.dueDate,
      projectId: projectId ?? this.projectId,
      project: project ?? this.project,
      tags: tags ?? this.tags,
      created: created,
      updated: updated,
    );
  }
}
