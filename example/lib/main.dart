import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'shared/providers/pocketbase_provider.dart';
import 'shared/utils/seed_data.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load startup dependencies in parallel
  final startupData = await Future.wait([
    SharedPreferences.getInstance(),
    rootBundle.loadString('assets/pb_schema.json'),
  ]);

  final sharedPreferences = startupData[0] as SharedPreferences;
  final schemaJson = startupData[1] as String;

  // The schema must be cached before any record is written or validated.
  final client = await createPocketBaseClient(sharedPreferences, schemaJson);

  // Seed sample projects and tasks if database is newly initialized
  await seedInitialDataIfEmpty(client);

  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(sharedPreferences),
      pocketBaseProvider.overrideWith((ref) {
        ref.onDispose(client.close);
        return client;
      }),
    ],
  );

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const TaskFlowApp(),
    ),
  );
}

class TaskFlowApp extends ConsumerWidget {
  const TaskFlowApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'TaskFlow — PocketBase Drift Demo',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      routerConfig: router,
    );
  }
}
