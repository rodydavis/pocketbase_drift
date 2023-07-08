# PocketBase Drift

[PocketBase](https://pub.dev/packages/pocketbase) client cached with [Drift](https://pub.dev/packages/drift).

- Full Text Search
- Offline first
- Partial updates
- CRUD support
- SQLite storage
- All platforms supported
- [Example app](/example/)
- Tests

## Getting Started

Replace a pocketbase client with a drift client.

```diff
- import 'package:pocketbase/pocketbase.dart';
+ import 'package:pocketbase_drift/pocketbase_drift.dart';

- final client = PocketBase(
+ final client = $PocketBase.database(
    'http://127.0.0.1:8090',
);
```

## Web

For web, you need to follow the instructions for [Drift](https://drift.simonbinder.eu/web/#drift-wasm) to copy the [sqlite wasm](https://github.com/simolus3/sqlite3.dart/releases) binary into the `web/` directory.

## TODO

- [X] Add support for offline mutations and retry
- [X] Add tests to cover offline actions
- [X] Authentication persistence
- [X] Offline collections
- [X] Offline records
- [X] Full text search for all local records
- [ ] Add support for fields (select)
- [ ] Add support for sort
- [ ] Add support validation of create/update for required fields
- [ ] Add support for files (and local)