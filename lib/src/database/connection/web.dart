import 'dart:async';

// ignore: avoid_web_libraries_in_flutter

import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';
import 'package:flutter/foundation.dart';

DatabaseConnection connect(
  String dbName, {
  bool logStatements = false,
}) {
  return DatabaseConnection.delayed(Future(() async {
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
