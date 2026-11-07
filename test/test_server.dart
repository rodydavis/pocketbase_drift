import 'dart:io';

/// Base URL of the PocketBase test server (`PB_URL`, default
/// `http://127.0.0.1:8090`). See `test/test-instruction.md`.
final String testServerUrl =
    Platform.environment['PB_URL'] ?? 'http://127.0.0.1:8090';
