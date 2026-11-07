import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocketbase_drift/pocketbase_drift.dart';

import '../../../shared/providers/pocketbase_provider.dart';
import '../models/task_model.dart';
import '../repositories/task_repository.dart';

/// Repository provider for tasks.
final taskRepositoryProvider = Provider<TaskRepository>((ref) {
  return TaskRepository(ref.watch(pocketBaseProvider));
});

/// Filter provider for selecting tasks by project.
final selectedProjectFilterProvider = StateProvider<String?>((ref) => null);

/// Filter provider for task completion tab (null: all, false: active, true: completed).
final completionFilterProvider = StateProvider<bool?>((ref) => null);

/// Reactive stream provider for tasks query state.
final tasksStateProvider =
    StreamProvider.autoDispose<QueryState<List<TaskModel>>>((ref) {
  final repo = ref.watch(taskRepositoryProvider);
  final policy = ref.watch(activeRequestPolicyProvider);
  final projectId = ref.watch(selectedProjectFilterProvider);
  final isCompleted = ref.watch(completionFilterProvider);

  return repo.watchTasksState(
    projectId: projectId,
    isCompleted: isCompleted,
    requestPolicy: policy,
  );
});

/// Single task stream provider by ID.
final singleTaskStateProvider = StreamProvider.autoDispose
    .family<QueryState<TaskModel?>, String>((ref, id) {
  final repo = ref.watch(taskRepositoryProvider);
  final policy = ref.watch(activeRequestPolicyProvider);
  return repo.watchTaskState(id, requestPolicy: policy);
});
