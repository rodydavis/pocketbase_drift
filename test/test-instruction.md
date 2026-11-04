# Test instructions

Most tests run against an in-memory database. The integration tests under
`test/services/` (and a few others) need a PocketBase server at
`http://127.0.0.1:8090`; use the backend bundled with the example app, which
creates the test collections (`todo`, `ultimate`, `active_todo`) and the
superuser `test@admin.com` / `Password123` on first start.

1. Requires Go 1.27+. Build and start the backend:
   ```bash
   cd example/backend && go build -o bin/server . && ./bin/server serve --http=127.0.0.1:8090
   ```
   Data is stored in `example/backend/pb_data/`; delete that directory to
   start from a clean server.
2. From the repository root, run the tests: `flutter test`
   (or a single file, e.g. `flutter test test/services/records_crud_test.dart`).

`dart_test.yaml` sets `concurrency: 1`, so `flutter test` runs the test files
one at a time. All files share one server and its collections, and the
integration suite changes server-wide fault modes. Do not override the
concurrency with `-j`/`--concurrency`.

## Integration suite

`test/integration/` holds the regression tests for the defects of the
2026-11-04 review. Each test name starts with the defect id (`Pxx`). The tests
use the lab collections and the `/api/lab/*` fault-injection routes of the
example backend (fail with 503, drop or hang requests, add latency, read
request stats, change records on the server).

1. Start the backend:
   ```bash
   cd example/backend && go run . serve --http=127.0.0.1:8090
   ```
2. From the repository root, run the suite:
   ```bash
   flutter test test/integration
   ```

Set `PB_URL` to use another server address, for example
`PB_URL=http://127.0.0.1:8091 flutter test test/integration`. The credentials
come from `example/backend/config/collections.go`. Override them with
`LAB_EMAIL`, `LAB_PASSWORD`, `LAB2_EMAIL`, `PB_SUPERUSER_EMAIL` and
`PB_SUPERUSER_PASSWORD`. The suite fails at start when the server cannot be
reached.

## Widget tests

Create the `$PocketBase` client outside the fake-async zone (for example in
`setUp`, not inside `testWidgets`). Then `await client.syncCompleted` in
`setUp`. The client starts a sync pass when it is created. A database query
that still runs on real time blocks the queries of the fake-async zone.

## Test schema

The server schema for the test collections comes from
`example/backend/migrations/0003_package_tests.json`, which mirrors
`test/test_data/test-pb_schema.json` and the local schema in
`test/test_data/collections.json.dart`. Keep the three in sync when changing
the test schema.
