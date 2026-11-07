import 'package:pocketbase_drift/pocketbase_drift.dart';

import '../../core/constants/app_constants.dart';

/// Seeds sample projects and tasks into the local database if empty.
/// This allows beginners exploring the example app to interact with tasks, relations,
/// filters, and streams immediately without needing an active server connection.
Future<void> seedInitialDataIfEmpty($PocketBase client) async {
  final projectsColl = client.collection(AppConstants.collectionProjects);
  final tasksColl = client.collection(AppConstants.collectionTasks);

  // Check if projects already exist locally
  final existingProjects = await projectsColl.getFullList(
    requestPolicy: RequestPolicy.cacheOnly,
  );
  if (existingProjects.isNotEmpty) return;

  // 1. Create sample projects
  final projMobile = await projectsColl.create(
    body: {
      'name': 'Mobile App 2.0',
      'description':
          'Offline-first Flutter app architecture using Drift SQLite',
      'color': '#6366F1',
      'icon': 'phone_android',
    },
    requestPolicy: RequestPolicy.cacheFirst,
  );

  final projBackend = await projectsColl.create(
    body: {
      'name': 'PocketBase Cloud',
      'description':
          'Go backend migrations, schema exports, and realtime hooks',
      'color': '#10B981',
      'icon': 'cloud',
    },
    requestPolicy: RequestPolicy.cacheFirst,
  );

  final projDesign = await projectsColl.create(
    body: {
      'name': 'Design System',
      'description':
          'Material 3 theme tokens, typography, and responsive cards',
      'color': '#F59E0B',
      'icon': 'palette',
    },
    requestPolicy: RequestPolicy.cacheFirst,
  );

  // 2. Create sample tasks with relations
  final sampleTasks = [
    {
      'title': 'Setup PocketBase Drift with Schema Caching',
      'description':
          'Initialize \$PocketBase.database with \$AuthStore.prefs and call client.setSchema(schemaJson).',
      'is_completed': true,
      'priority': 'urgent',
      'due_date': 'Today',
      'project': projMobile.id,
      'tags': 'drift, setup, schema',
    },
    {
      'title': 'Test Reactive Streams with QueryState',
      'description':
          'Observe watchRecordsState to eliminate UI loading flashes and seamlessly inspect isFetchingNetwork.',
      'is_completed': true,
      'priority': 'high',
      'due_date': 'Today',
      'project': projMobile.id,
      'tags': 'streams, reactive, riverpod',
    },
    {
      'title': 'Inspect 5 Request Policies in Action',
      'description':
          'Switch between cacheFirst, cacheAndNetwork, networkFirst, cacheOnly, and networkOnly.',
      'is_completed': false,
      'priority': 'medium',
      'due_date': 'Tomorrow',
      'project': projMobile.id,
      'tags': 'policy, caching',
    },
    {
      'title': 'Export PocketBase Schema (pb_schema.json)',
      'description':
          'Download collection schemas from PocketBase Admin UI and place inside assets/pb_schema.json.',
      'is_completed': false,
      'priority': 'high',
      'due_date': 'Next Week',
      'project': projBackend.id,
      'tags': 'pocketbase, backend',
    },
    {
      'title': 'Design Material 3 Theme Tokens',
      'description':
          'Configure harmonious light and dark color schemes with rounded card elevations.',
      'is_completed': true,
      'priority': 'low',
      'due_date': 'This Week',
      'project': projDesign.id,
      'tags': 'ui, material3, theme',
    },
  ];

  for (final taskData in sampleTasks) {
    await tasksColl.create(
      body: taskData,
      requestPolicy: RequestPolicy.cacheFirst,
    );
  }
}
