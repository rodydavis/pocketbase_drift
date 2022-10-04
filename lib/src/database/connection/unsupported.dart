import 'package:drift/drift.dart';

DatabaseConnection connect(
  String dbName, {
  bool useWebWorker = false,
  bool logStatements = false,
}) {
  throw UnsupportedError(
    'No suitable database implementation was found on this platform.',
  );
}
