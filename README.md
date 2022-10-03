# PocketBase Drift

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
+ final client = PocketBaseDrift(
    'http://127.0.0.1:8090'
);
```
