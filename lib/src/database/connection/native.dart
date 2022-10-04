import 'dart:io';
import 'dart:isolate';

import 'package:drift/drift.dart';
import 'package:drift/isolate.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

DatabaseConnection connect(
  String dbName, {
  bool useWebWorker = false,
  bool logStatements = false,
}) {
  return DatabaseConnection.delayed(Future.sync(() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(appDir.path, dbName);

    final receiveDriftIsolate = ReceivePort();
    await Isolate.spawn(_entrypointForDriftIsolate,
        _IsolateStartRequest(receiveDriftIsolate.sendPort, dbPath));

    final driftIsolate = await receiveDriftIsolate.first as DriftIsolate;
    return driftIsolate.connect();
  }));
}

class _IsolateStartRequest {
  final SendPort talkToMain;
  final String databasePath;

  _IsolateStartRequest(this.talkToMain, this.databasePath);
}

void _entrypointForDriftIsolate(_IsolateStartRequest request) {
  final databaseImpl = NativeDatabase(
    File(request.databasePath),
    logStatements: false,
  );

  final driftServer = DriftIsolate.inCurrent(
    () => DatabaseConnection(databaseImpl),
  );

  request.talkToMain.send(driftServer);
}
