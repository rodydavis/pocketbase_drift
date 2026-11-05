import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' show Database;

/// Runs inside the database isolate when the connection opens.
void _configure(Database db) {
  // WAL: readers do not block on writers and commits are cheaper.
  db.execute('PRAGMA journal_mode = WAL;');
  db.execute('PRAGMA busy_timeout = 5000;');
  // A large write (e.g. a big file) grows the WAL; truncate it back to
  // 8 MB at the next checkpoint instead of keeping its high-water mark.
  db.execute('PRAGMA journal_size_limit = 8388608;');
}

/// Opens the cache database.
///
/// File databases run SQLite in a background isolate, so queries, batch
/// writes and blob reads never block the UI isolate. [inMemory] databases
/// (tests) stay on the calling isolate.
DatabaseConnection connect(
  String dbName, {
  bool logStatements = false,
  bool inMemory = false,
}) {
  if (inMemory) {
    return DatabaseConnection(NativeDatabase.memory());
  }

  return DatabaseConnection.delayed(Future.sync(() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(appDir.path, dbName);

    return DatabaseConnection(NativeDatabase.createInBackground(
      File(dbPath),
      logStatements: logStatements,
      setup: _configure,
    ));
  }));
}
