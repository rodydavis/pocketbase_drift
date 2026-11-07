# TaskFlow — PocketBase Drift Example Application

A modern, production-grade reference application demonstrating how to build **offline-first Flutter apps** backed by PocketBase using the `pocketbase_drift` client and Drift SQLite.

---

## 🌟 What This Example Demonstrates

1. **Client Initialization & Schema Caching (`setSchema`)**
   - Initializes `$PocketBase.database` with persistent `$AuthStore.prefs`.
   - `createPocketBaseClient(prefs, schemaJson)` awaits `client.setSchema(...)` with `assets/pb_schema.json` before the app starts, so the first writes and queries see every collection. `main.dart` overrides `pocketBaseProvider` with this client.

2. **5 Request Policies in Action**
   - **`cacheAndNetwork` (Default):** Streams serve cached local SQLite data instantly, fetch updates from the remote PocketBase server, update SQLite, and re-emit. Writes go to the server first and are queued only when the server is unreachable.
   - **`cacheFirst`:** Serves local cache immediately and refreshes it once from the server in the background. Waits for the server only when the cache is empty. Writes go to the cache first and sync in the background.
   - **`networkFirst`:** Tries remote PocketBase server first, falling back to local SQLite cache if offline.
   - **`cacheOnly`:** Reads strictly from local SQLite, bypassing network requests entirely.
   - **`networkOnly`:** Bypasses local database completely.

3. **Reactive Streams & `QueryState<T>`**
   - Uses `watchRecordsState` and `watchRecordState` with `QueryState<T>` in Riverpod `StreamProvider`s.
   - Eliminates empty-screen flickering on startup while providing `isFetchingNetwork` and `error` indicators to UI widgets.

4. **Local-First Mutations & Sync Queue Diagnostics**
   - Creating, editing, and deleting records uses the active policy. With `cacheFirst` the change is written to local Drift SQLite immediately. With `cacheAndNetwork` it is queued locally when the server is unreachable; a server rejection is shown as an error.
   - Live **Sync Diagnostics** tab lists pending unsynced mutations (`client.db.pendingRecords().watch()`) and starts a manual sync (`client.syncPendingChanges()`).

5. **Relation Expansion & Full-Text Search**
   - Demonstrates local and remote relation expansion (`expand: 'project'`).
   - Local database search filtering across tasks and projects without network round-trips.

---

## 🚀 Running the Example

### 1. Instant Offline Exploration (No Backend Required)
You can run the example app immediately out-of-the-box. If no PocketBase server is connected, the app automatically seeds sample projects and tasks into local Drift SQLite:

```bash
flutter run
```

### 2. Connected with the Bundled PocketBase Backend (Optional)
`example/backend/` is a Go PocketBase (v0.40.6) server with every collection the example app and the package tests need, applied by migrations on first start:

- `projects` and `tasks` (same schema as `assets/pb_schema.json`, public rules) for this app.
- `todo`, `ultimate` and the `active_todo` view (from `test/test_data/test-pb_schema.json`) plus the superuser `test@admin.com` / `Password123` for the package's integration tests in `test/`.
- Extra review-lab collections (`posts`, `notes`, `locked`, `events`, `big`), the users `lab@example.com` / `lab2@example.com`, and control routes under `/api/lab/*` (request stats, chaos injection, server-side mutations). The control routes have no auth: only bind the server to `127.0.0.1`.

Requires Go 1.27+.

1. Build and start the backend (data goes to `example/backend/pb_data/`, delete it to start fresh):
   ```bash
   cd example/backend && go build -o bin/server . && ./bin/server serve --http=127.0.0.1:8090
   ```
2. Run the Flutter app (`http://127.0.0.1:8090` is also the default URL):
   ```bash
   flutter run --dart-define=POCKETBASE_URL=http://127.0.0.1:8090
   ```
   On an Android emulator or device, forward the port first with `adb reverse tcp:8090 tcp:8090`. Debug and profile builds allow cleartext HTTP for this; release builds do not.
3. Package tests: with the backend running, run `flutter test` from the repository root (see `test/test-instruction.md`).

---

## 📂 Project Architecture

```
lib/
├── core/
│   ├── constants/        # App-wide constants and collection names
│   ├── router/           # GoRouter setup with bottom navigation tabs
│   └── theme/            # Material 3 light/dark themes
├── features/
│   ├── tasks/            # Tasks domain (models, repository, providers, UI)
│   ├── projects/         # Projects domain (relations demonstration)
│   ├── sync/             # Sync diagnostics & pending mutation inspector
│   └── search/           # Instant local SQLite search
├── shared/
│   ├── providers/        # pocketBaseProvider, sharedPreferencesProvider
│   ├── utils/            # Seed data helper for empty databases
│   └── widgets/          # EmptyState, ErrorView, FetchingIndicator, OfflineBanner
└── main.dart             # Parallel async startup & ProviderScope setup
```
