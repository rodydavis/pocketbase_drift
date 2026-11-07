import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pocketbase_drift/pocketbase_drift.dart';

import '../../../core/constants/app_constants.dart';
import '../../../shared/providers/pocketbase_provider.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../tasks/models/task_model.dart';
import '../../tasks/widgets/task_card.dart';

final searchQueryProvider = StateProvider.autoDispose<String>((ref) => '');

final searchResultsProvider =
    FutureProvider.autoDispose<List<TaskModel>>((ref) async {
  final query = ref.watch(searchQueryProvider).trim();
  if (query.isEmpty) return [];

  final client = ref.watch(pocketBaseProvider);

  // Search tasks locally using filter expressions in drift
  final records = await client
      .collection(AppConstants.collectionTasks)
      .getFullList(
        filter: 'title ~ "$query" || description ~ "$query" || tags ~ "$query"',
        expand: 'project',
        requestPolicy: RequestPolicy.cacheOnly,
      );

  return records.map(TaskModel.fromRecord).toList();
});

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(searchQueryProvider);
    final resultsAsync = ref.watch(searchResultsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Search Tasks'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search title, description, tags...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          ref.read(searchQueryProvider.notifier).state = '';
                        },
                      )
                    : null,
              ),
              onChanged: (val) {
                ref.read(searchQueryProvider.notifier).state = val;
              },
            ),
          ),
          Expanded(
            child: query.isEmpty
                ? const EmptyState(
                    title: 'Search Local Database',
                    message:
                        'Type keywords to query SQLite cache instantly without hitting the server.',
                    icon: Icons.search,
                  )
                : resultsAsync.when(
                    data: (results) {
                      if (results.isEmpty) {
                        return EmptyState(
                          title: 'No Matching Results',
                          message: 'No tasks matched "$query" in local cache.',
                          icon: Icons.search_off,
                        );
                      }

                      return ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: results.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final task = results[index];
                          return TaskCard(
                            task: task,
                            onTap: () => context.push('/tasks/${task.id}'),
                          );
                        },
                      );
                    },
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (err, _) => Center(
                      child: Text('Search error: $err'),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
