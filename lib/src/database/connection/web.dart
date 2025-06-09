import 'dart:async';

import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';
import 'package:flutter/foundation.dart';
import 'package:sqlite3/wasm.dart';

DatabaseConnection connect(
  String dbName, {
  bool logStatements = false,
  bool inMemory = false,
}) {
  return DatabaseConnection.delayed(Future(() async {
    if (inMemory) {
      final sqlite = await WasmSqlite3.loadFromUrl(
        Uri.parse('/sqlite3.wasm'),
      );
      sqlite.registerVirtualFileSystem(InMemoryFileSystem(), makeDefault: true);
      return DatabaseConnection(
        WasmDatabase.inMemory(
          sqlite,
          logStatements: logStatements,
        ),
      );
    }
    final result = await WasmDatabase.open(
      // prefer to only use valid identifiers here
      databaseName: dbName.replaceAll('.db', ''),
      sqlite3Uri: Uri.parse('/sqlite3.wasm'),
      driftWorkerUri: Uri.parse('/drift_worker.dart.js'),
    );

    if (result.missingFeatures.isNotEmpty) {
      // Depending how central local persistence is to your app, you may want
      // to show a warning to the user if only unreliable implementations
      // are available.
      if (kDebugMode) {
        print(
          'Using ${result.chosenImplementation} due to missing browser '
          'features: ${result.missingFeatures}',
        );
      }
    }

    return result.resolvedExecutor;
  }));
}
