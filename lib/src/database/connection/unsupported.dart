import 'package:drift/drift.dart';
import 'package:drift/native.dart';

DatabaseConnection connect(
  String dbName, {
  bool useWebWorker = false,
  bool logStatements = false,
}) {
  return DatabaseConnection(NativeDatabase.memory(
    logStatements: logStatements,
  ));
}
