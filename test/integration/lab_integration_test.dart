// Integration tests against the example backend (example/backend: PocketBase
// with the lab collections and the `/api/lab` chaos/stats routes). Tests of
// the 2026-11-04 review findings are named after them (Pxx).
//
// Needs the example backend running:
//
//   cd example/backend && go run . serve --http=127.0.0.1:8090
//   flutter test test/integration
//
// Set PB_URL to use another address (e.g. PB_URL=http://127.0.0.1:8091).
// Credentials default to example/backend/config/collections.go; override
// with LAB_EMAIL, LAB_PASSWORD, LAB2_EMAIL, PB_SUPERUSER_EMAIL,
// PB_SUPERUSER_PASSWORD.
//
// Chaos modes and realtime drops are global to the server, so all areas run
// from this single file, one test at a time.
@Timeout(Duration(seconds: 90))
library;

import 'package:flutter_test/flutter_test.dart';

import 'batch.dart';
import 'connectivity_errors.dart';
import 'filters_ttl.dart';
import 'realtime_watchers.dart';
import 'session_expiry.dart';
import 'support.dart';
import 'sync_correctness.dart';

void main() {
  registerIntegrationHooks();

  connectivityErrorTests();
  syncCorrectnessTests();
  realtimeWatcherTests();
  filterTtlTests();
  batchTests();
  sessionExpiryTests();
}
