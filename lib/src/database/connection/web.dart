import 'dart:async';

// ignore: avoid_web_libraries_in_flutter
import 'dart:html';

import 'package:drift/drift.dart';
import 'package:drift/remote.dart';
import 'package:drift/web.dart';
import 'package:drift/wasm.dart';
import 'package:http/http.dart' as http;
import 'package:sqlite3/wasm.dart';

DatabaseConnection connect(
  String dbName, {
  bool useWebWorker = false,
  bool logStatements = false,
}) {
  if (useWebWorker) {
    final worker = SharedWorker('shared_worker.dart.js');
    return remote(worker.port!.channel());
  } else {
    return DatabaseConnection.delayed(Future.sync(() async {
      final response = await http.get(Uri.parse('sqlite3.wasm'));
      final fs = await IndexedDbFileSystem.open(dbName: '/db/');
      final path = '/drift/db/$dbName';
      final sqlite3 = await WasmSqlite3.load(
        response.bodyBytes,
        SqliteEnvironment(fileSystem: fs),
      );
      final databaseImpl = WasmDatabase(
        sqlite3: sqlite3,
        path: path,
        fileSystem: fs, // <- this is required but not documented
        logStatements: logStatements,
      );
      return DatabaseConnection(databaseImpl);
    }));
  }
}
