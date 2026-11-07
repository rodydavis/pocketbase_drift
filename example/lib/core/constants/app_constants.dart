/// App-wide constants and PocketBase configuration defaults.
abstract class AppConstants {
  static const String appName = 'TaskFlow';
  static const String appTagline = 'PocketBase Drift Offline-First Demo';

  /// Default PocketBase server URL (configurable via --dart-define or UI).
  static const String defaultServerUrl = String.fromEnvironment(
    'POCKETBASE_URL',
    defaultValue: 'http://127.0.0.1:8090',
  );

  /// SQLite database filename used by drift.
  static const String databaseName = 'taskflow.db';

  /// SharedPreferences key for persisting PocketBase auth state.
  static const String keyPbAuth = 'pb_auth';

  /// SharedPreferences key for active request policy.
  static const String keyRequestPolicy = 'app_request_policy';

  /// Collections in schema
  static const String collectionTasks = 'tasks';
  static const String collectionProjects = 'projects';
}
