/// A powerful, offline-first Flutter client for PocketBase, backed by the
/// reactive persistence of Drift (the Flutter & Dart flavor of `moor`).
///
/// This library extends the official PocketBase Dart SDK to provide a seamless
/// offline-first experience. It automatically caches data from your PocketBase
/// instance into a local SQLite database, allowing your app to remain fully
/// functional even without a network connection. Changes made while offline are
/// queued and automatically retried when connectivity is restored.
///
/// Key features include:
/// - Offline CRUD operations.
/// - Automatic data synchronization.
/// - Reactive data streams for UI updates.
/// - Local caching of collections and records using Drift.
/// - Powerful local querying capabilities (filtering, sorting, pagination).
/// - Relation expansion from the local cache.
/// - Full-text search on cached data.
/// - Authentication persistence.
/// - File and image caching with `PocketBaseImageProvider`.
///
/// To get started, replace your standard `PocketBase` client with
/// `$PocketBase.database()` from this package.
library;

export 'image.dart';
export 'src/database/connection/connection.dart';
export 'src/database/database.dart';
export 'src/database/filter_parser.dart';
export 'src/pocketbase/pocketbase.dart';
export 'src/pocketbase/services/records.dart';
export 'src/pocketbase/services/collections.dart';
export 'src/pocketbase/services/connectivity.dart';
export 'src/pocketbase/services/backup.dart';
export 'src/pocketbase/services/files.dart';
export 'src/pocketbase/services/health.dart';
export 'src/pocketbase/services/logs.dart';
export 'src/pocketbase/services/realtime.dart';
export 'src/pocketbase/services/settings.dart';
export 'src/pocketbase/services/service.dart';
export 'src/pocketbase/stores/auth.dart';

export 'package:pocketbase/pocketbase.dart';
