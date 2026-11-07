import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocketbase_drift/pocketbase_drift.dart';

import '../../../shared/providers/pocketbase_provider.dart';
import '../models/project_model.dart';
import '../repositories/project_repository.dart';

/// Repository provider for projects.
final projectRepositoryProvider = Provider<ProjectRepository>((ref) {
  return ProjectRepository(ref.watch(pocketBaseProvider));
});

/// Reactive stream provider for projects state.
final projectsStateProvider =
    StreamProvider.autoDispose<QueryState<List<ProjectModel>>>((ref) {
  final repo = ref.watch(projectRepositoryProvider);
  final policy = ref.watch(activeRequestPolicyProvider);
  return repo.watchProjectsState(requestPolicy: policy);
});

/// Simple list of projects derived from state.
final projectsListProvider = Provider.autoDispose<List<ProjectModel>>((ref) {
  final state = ref.watch(projectsStateProvider).valueOrNull;
  return state?.data ?? [];
});
