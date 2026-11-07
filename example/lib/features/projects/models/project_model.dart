import 'package:pocketbase_drift/pocketbase_drift.dart';

/// Typed domain model representing a Project.
class ProjectModel {
  const ProjectModel({
    required this.id,
    required this.name,
    this.description = '',
    this.color = '#6366F1',
    this.icon = 'folder',
    this.created,
    this.updated,
  });

  final String id;
  final String name;
  final String description;
  final String color;
  final String icon;
  final String? created;
  final String? updated;

  factory ProjectModel.fromRecord(RecordModel record) {
    return ProjectModel(
      id: record.id,
      name: record.getStringValue('name'),
      description: record.getStringValue('description'),
      color: record.getStringValue('color', '#6366F1'),
      icon: record.getStringValue('icon', 'folder'),
      created: record.getStringValue('created'),
      updated: record.getStringValue('updated'),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'description': description,
      'color': color,
      'icon': icon,
    };
  }

  ProjectModel copyWith({
    String? id,
    String? name,
    String? description,
    String? color,
    String? icon,
  }) {
    return ProjectModel(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      color: color ?? this.color,
      icon: icon ?? this.icon,
      created: created,
      updated: updated,
    );
  }
}
