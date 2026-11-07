import 'package:pocketbase_drift/pocketbase_drift.dart';

import '../../../core/constants/app_constants.dart';
import '../models/project_model.dart';

class ProjectRepository {
  ProjectRepository(this._client);

  final $PocketBase _client;

  $RecordService get _collection =>
      _client.collection(AppConstants.collectionProjects);

  /// Streams all projects with reactive query state (cached data + background fetch status).
  Stream<QueryState<List<ProjectModel>>> watchProjectsState({
    RequestPolicy requestPolicy = RequestPolicy.cacheAndNetwork,
  }) {
    return _collection
        .watchRecordsState(
          sort: 'name',
          requestPolicy: requestPolicy,
        )
        .map(
          (state) => QueryState(
            data: state.data.map(ProjectModel.fromRecord).toList(),
            isFetchingNetwork: state.isFetchingNetwork,
            error: state.error,
          ),
        );
  }

  /// Creates a new project with local-first optimistic write.
  Future<ProjectModel> createProject({
    required String name,
    String description = '',
    String color = '#6366F1',
    String icon = 'folder',
    RequestPolicy requestPolicy = RequestPolicy.cacheAndNetwork,
  }) async {
    final record = await _collection.create(
      body: {
        'name': name,
        'description': description,
        'color': color,
        'icon': icon,
      },
      requestPolicy: requestPolicy,
    );
    return ProjectModel.fromRecord(record);
  }

  /// Updates an existing project.
  Future<ProjectModel> updateProject(
    String id, {
    String? name,
    String? description,
    String? color,
    String? icon,
    RequestPolicy requestPolicy = RequestPolicy.cacheAndNetwork,
  }) async {
    final data = <String, dynamic>{};
    if (name != null) data['name'] = name;
    if (description != null) data['description'] = description;
    if (color != null) data['color'] = color;
    if (icon != null) data['icon'] = icon;

    final record = await _collection.update(
      id,
      body: data,
      requestPolicy: requestPolicy,
    );
    return ProjectModel.fromRecord(record);
  }

  /// Deletes a project.
  Future<void> deleteProject(
    String id, {
    RequestPolicy requestPolicy = RequestPolicy.cacheAndNetwork,
  }) async {
    await _collection.delete(id, requestPolicy: requestPolicy);
  }
}
