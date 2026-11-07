import 'package:pocketbase_drift/pocketbase_drift.dart';

import '../../../core/constants/app_constants.dart';
import '../models/task_model.dart';

class TaskRepository {
  TaskRepository(this._client);

  final $PocketBase _client;

  $RecordService get _collection =>
      _client.collection(AppConstants.collectionTasks);

  /// Streams all tasks with reactive query state (cached data + background fetch status + relation expansion).
  Stream<QueryState<List<TaskModel>>> watchTasksState({
    String? projectId,
    bool? isCompleted,
    RequestPolicy requestPolicy = RequestPolicy.cacheAndNetwork,
  }) {
    final filters = <String>[];
    if (projectId != null && projectId.isNotEmpty) {
      filters.add('project = "$projectId"');
    }
    if (isCompleted != null) {
      filters.add('is_completed = $isCompleted');
    }

    final filterStr = filters.isEmpty ? null : filters.join(' && ');

    return _collection
        .watchRecordsState(
          filter: filterStr,
          sort: '-created',
          expand: 'project',
          requestPolicy: requestPolicy,
        )
        .map(
          (state) => QueryState(
            data: state.data.map(TaskModel.fromRecord).toList(),
            isFetchingNetwork: state.isFetchingNetwork,
            error: state.error,
          ),
        );
  }

  /// Streams a single task by ID with relation expansion.
  Stream<QueryState<TaskModel?>> watchTaskState(
    String id, {
    RequestPolicy requestPolicy = RequestPolicy.cacheAndNetwork,
  }) {
    return _collection
        .watchRecordState(
          id,
          expand: 'project',
          requestPolicy: requestPolicy,
        )
        .map(
          (state) => QueryState(
            data: state.data != null ? TaskModel.fromRecord(state.data!) : null,
            isFetchingNetwork: state.isFetchingNetwork,
            error: state.error,
          ),
        );
  }

  /// Creates a task with local-first optimistic cache write.
  Future<TaskModel> createTask({
    required String title,
    String description = '',
    bool isCompleted = false,
    TaskPriority priority = TaskPriority.medium,
    String? dueDate,
    String? projectId,
    String tags = '',
    RequestPolicy requestPolicy = RequestPolicy.cacheAndNetwork,
  }) async {
    final record = await _collection.create(
      body: {
        'title': title,
        'description': description,
        'is_completed': isCompleted,
        'priority': priority.name,
        'due_date': dueDate ?? '',
        'project': projectId ?? '',
        'tags': tags,
      },
      requestPolicy: requestPolicy,
    );
    return TaskModel.fromRecord(record);
  }

  /// Updates an existing task.
  Future<TaskModel> updateTask(
    String id, {
    String? title,
    String? description,
    bool? isCompleted,
    TaskPriority? priority,
    String? dueDate,
    String? projectId,
    String? tags,
    RequestPolicy requestPolicy = RequestPolicy.cacheAndNetwork,
  }) async {
    final data = <String, dynamic>{};
    if (title != null) data['title'] = title;
    if (description != null) data['description'] = description;
    if (isCompleted != null) data['is_completed'] = isCompleted;
    if (priority != null) data['priority'] = priority.name;
    if (dueDate != null) data['due_date'] = dueDate;
    if (projectId != null) data['project'] = projectId;
    if (tags != null) data['tags'] = tags;

    final record = await _collection.update(
      id,
      body: data,
      requestPolicy: requestPolicy,
    );
    return TaskModel.fromRecord(record);
  }

  /// Toggles task completion status.
  Future<TaskModel> toggleTask(
    String id,
    bool currentStatus, {
    RequestPolicy requestPolicy = RequestPolicy.cacheAndNetwork,
  }) async {
    return updateTask(
      id,
      isCompleted: !currentStatus,
      requestPolicy: requestPolicy,
    );
  }

  /// Deletes a task.
  Future<void> deleteTask(
    String id, {
    RequestPolicy requestPolicy = RequestPolicy.cacheAndNetwork,
  }) async {
    await _collection.delete(id, requestPolicy: requestPolicy);
  }
}
