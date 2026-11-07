## 0.7.1

### Fixes

- **An expired session no longer empties the cache or drops queued changes.** PocketBase answers a request with an expired token as a guest: owner-scoped list rules (`owner = @request.auth.id`) return no rows, and reads, updates and deletes of the account's records get 404. 0.7.0 replaced the cached rows with that empty answer (live-query refreshes after a realtime reconnect, `getFullList`), removed cached records on the 404 (`getOne`), and the sync dropped queued updates as "deleted on the server", treated queued deletes as done and counted rejected creates towards `localSyncRetryCount`. While the auth store holds an expired token (`client.hasExpiredSession`), the package now treats the server like an unreachable one for cache-backed work:
  - Sync pauses; queued changes stay pending. `pushPending` returns `PushOutcome.retryLater`. A request whose token expired while it was in flight is retried later, not dropped or counted.
  - Live queries keep the cache and do not refresh.
  - Record reads with `cacheFirst`, `networkFirst` or `cacheAndNetwork` (and collection reads) answer from the cache without a request. A cache miss throws `ClientException` with status 401.
  - `cacheAndNetwork` writes and batches are queued; the background send of `cacheFirst` writes and batches waits.
  - `networkOnly` and `networkFirst` writes still go to the server, but a 404 no longer removes the cached record.
  - A login or token refresh that leaves a valid token resumes the work: queued changes sync and the paused live queries refresh. Before, a token refresh of the same account did not start a sync.
  - Not detected: a token the server revoked before its expiry. Check the session with `authRefresh()` at start and on resume. See "Expired sessions" in the README.
- **Realtime no longer shows the previous account's records after a logout or an account switch.** PocketBase keeps the auth that a realtime connection had when its subscriptions were sent, and allows no change except guest → account; the SDK sends the subscriptions again only for new topics. With a live query open across a logout or an account switch, the connection kept the previous account's auth, and its events were written to the cache, where the guest or the next account saw them. A login after a realtime reconnect with an expired token left a guest connection that got no events of the account. Now:
  - On a login, a logout, an account switch or a login after an expired session, the client ends the realtime connection; the SDK reconnects and sends all subscriptions (the app's own too) with the current token, and the live queries refetch. A token refresh of the same account keeps the connection.
  - Until the reconnect, events of a connection that is still authenticated as another account are dropped: they do not reach the cache, the live queries or `collection(...).subscribe` callbacks (`client.realtimeMatchesSession`).
- **A killed first start no longer leaves a broken database.** The schema is created in one transaction that also writes `user_version`. A database that 0.7.0 or earlier left half-created (the process died during the first open; every later open failed with `trigger blob_files_delete already exists`) is repaired on the next open: the leftover tables, indexes and triggers of the package are dropped and created again. Such a database holds no data.
- **A killed upgrade no longer leaves a broken database.** Upgrades run in one transaction that also writes `user_version`. A v3 → v4 upgrade that 0.7.0 left unfinished (for example `duplicate column name: cachedAt` on every later open) finishes on the next open.

### New

- **`client.hasExpiredSession`.** `true` when the auth store has a token whose `exp` has passed (the rule of `authStore.isValid`). An empty token (a guest) is not an expired session.
- **`client.onSessionExpired`.** A `Stream<void>` that emits when the package first pauses work because the session expired, and again only after a valid login. Use it to ask the user to log in again; also check `hasExpiredSession` when you start listening.
- **`RequestPolicy.fetch(authScoped:)`.** Marks reads whose answer depends on the logged-in account; the package's record and collection reads set it.
- **`client.realtimeMatchesSession`.** `false` while the realtime connection is still authenticated as an account other than the logged-in one; realtime events are dropped then.

### Behaviour changes

- A token that is not a JWT counts as an expired session, like in `authStore.isValid`. Tests with a mock server that log in with a placeholder token (`'token'`) must use a JWT with a future `exp`, or sync and live-query refreshes pause.
- `client.httpClientFactory` returns clients that wrap the clients of the configured factory: the client hands out the realtime (SSE) response through a stream it can end, to reconnect after an account change. Other requests pass through unchanged.

## 0.7.0

### Breaking changes

- **Server answers are no longer hidden behind the cache.** Reads (`getOne`, `getList`, `getFullList`, `getFirstListItem`, cached `send` GETs) fall back to the cache only when the server is unreachable: status 0, timeout, socket error, 408, 429 or 5xx. A 4xx answer (400, 401, 403, 404) is thrown as `ClientException` with the server status. Callers that relied on cached data after a 403 or 404 must catch `ClientException` and decide themselves.
  - A `getOne` 404 removes the stale cached copy, unless the row has unsynced local changes. A record created offline and not yet synced is returned from the cache.
  - When the server is unreachable and nothing is cached, the read throws `ClientException` with status 0 (was a generic `Exception`). Replace `on Exception` checks with `on ClientException catch (e)` and test `e.statusCode == 0`. Package cache misses use the new exported `CacheMissException`.
- **`cacheAndNetwork` writes queue only when the server is unreachable.** The rule is the same as for reads. A rejection (400 validation, 403 rule) is thrown and nothing is stored locally. Callers must handle the `ClientException` (for example show the validation errors).
- **`networkFirst` update no longer creates.** A 404 or 400 answer is thrown. It was turned into a create. Call `create` yourself when you want an upsert.
- **Strict writes report an unreachable server as status 0.** `networkOnly` and `networkFirst` create, update and delete convert connectivity failures (no connection, socket or HTTP client errors, `requestTimeout` elapsed) to `ClientException` with status 0. `originalError` holds the cause. A 502, 503 or 504 answer stays the server's `ClientException`. Replace `on TimeoutException` and `on SocketException` handlers with a `statusCode == 0` check.
- **Sync sends only the changed fields.** For an update, sync sends the fields changed locally (`pendingFields`). For a create, it sends the whole record. File uploads are sent once as multipart parts and are not re-uploaded on later edits. Changes from other devices to other fields are kept. A field changed only with `+`/`-` modifiers is sent as a modifier, so changes from other devices to that field are kept too (see "Queued modifier edits sync as deltas" in Fixes). No caller change is necessary.
- **Rejected changes are parked, not deleted.** After `localSyncRetryCount` rejections, the row stays in the cache with a `syncError` map (`status`, `message`, `data`, `at`). The failure is reported on `client.syncFailures`. Automatic sync skips the row. Retry it with `client.syncPendingChanges(includeFailed: true)` or `retryLocal(includeFailed: true)`. Remove it with `client.discardPendingChange(collection, id)`. An offline update of a record that was deleted on the server is dropped and reported with `SyncFailure.dropped == true`. Apps that expected the row to disappear must listen to `syncFailures` and discard or retry.
- **`retryLocal` lost its unused `batch` parameter.** Remove the argument. The new `includeFailed` parameter also retries parked rows.
- **Logout keeps unsynced changes.** `authStore.clear()` with `clearOnLogout` (default `true`) deletes the cache except pending rows and their blobs. Pending rows belong to the account that wrote them (`pendingOwner`). Other accounts do not see them in reads, search or sync. They sync when that account logs in again. Call `client.db.clearAllData()` when logout must also discard unsynced changes.
- **Cache TTL uses the cache time.** `runMaintenance` expires rows by `cachedAt` (new column, database schema v4), not by the server's `updated` value. Rows fetched by list reads now expire too. `cleanupExpiredFiles` also removes the blobs of records that are no longer cached. The migration sets `cachedAt` of existing rows to the upgrade time.
- **Local filters follow the PocketBase quoting rules.** Date macros produce the PocketBase format in UTC (`2026-11-04 00:00:00.000Z`). `@yesterday` and `@tomorrow` are now ± 1 day, like the server. The parser accepts the `\"`, `\'` and `\\` escapes. `~` and `!~` escape `%` and `_` like the server. `@request.auth.id` on the right-hand side resolves to the logged-in account id (`client.authStore.record?.id`), or `""` when nobody is logged in, like the server. Other right-hand sides that the cache cannot evaluate (other `@request.*` values, `@collection.*`, field references) and `@` tokens on the left side throw `UnsupportedError`. A malformed filter throws `FormatException`. `FilterTerm`, `LogicalOperator` and `ValueType` are no longer exported. `FilterParser` has the new `now` and `authId` parameters. Use `networkOnly` for filters that the cache cannot evaluate.
- **`PocketBaseImageProvider` cleanup.** The `color` parameter and the static `getFilterColor` are removed (they had no effect). Remove these arguments. There is no fallback 100×100 decode. Providers with the same inputs are equal, so they share one `ImageCache` entry. A failed load is evicted, so the next build retries.
- **`getFileBytes` downloads have a timeout and typed errors.** The default `timeout` is 30 s. When the download fails and no cached copy exists, an unreachable server or a timeout throws `ClientException` with status 0 (`originalError` holds the cause). A non-200 answer throws the server's `ClientException` with the status, URL and response. A `cacheOnly` cache miss throws `CacheMissException` (was a generic `Exception`). `cacheFirst` now downloads on a cache miss or an expired copy (it threw). Thumbs (`thumb: '100x100'`) are cached separately from the original file. The file name parameter is `filename`.
- **`$PocketBase.setSchema` rethrows invalid schema JSON.** It was logged and swallowed. Catch the error if your schema source can be invalid.
- **`networkOnly` watchers stream server data.** `watchRecord*`/`watchRecords*` with `networkOnly` emitted an always-empty cache stream. They now emit the server's data and refetch on realtime events. With `limit`, `watchRecords` fetches only `limit` records from the server.
- **`statusStream` emits the current status once per listener.** Each new listener gets the current status first. Other listeners no longer receive re-emits.
- **The database runs in a background isolate.** The default (non-web) connection uses `NativeDatabase.createInBackground` with WAL. `inMemory: true` stays on the calling isolate.
- **Batch changes.** Creates and upserts without an `id` get a client-generated id. A `cacheAndNetwork` batch that the server rejects throws and stores nothing. Only an unreachable server queues the operations. Files passed to batch operations are now sent (they were ignored) and are replayed offline. `networkOnly` and `networkFirst` batches throw `ClientException` with status 0 when offline.
- **Example app: `schemaProvider` removed.** `createPocketBaseClient(prefs, schemaJson)` awaits `setSchema`. Override `pocketBaseProvider` at startup with the returned client.
- **Local writes never edit another account's pending change.** A local update or delete of a record with an unsynced change of another account (kept after logout) throws `StateError`. The change syncs when that account logs in again.
- **Size-limited file cache.** `maxFileCacheBytes` on `$PocketBase(...)` and `$PocketBase.database(...)` limits the file blob cache: downloaded files, thumbs and the cached copies of uploads. The default is `$PocketBase.defaultMaxFileCacheBytes`: 128 MB, 32 MB on the web (the IndexedDB fallback keeps the whole database in memory). Set `maxFileCacheBytes: null` to keep the 0.6.x behaviour (no limit).
  - After each blob write (download or cached upload copy), eviction runs in the background (one run at a time) and deletes blobs until the cache holds at most 90% of the limit (the eviction target): first the unpinned blobs larger than the target, then the least recently used ones. A cache hit updates the last access of a blob at most once per hour. A file renamed by the server after a push counts as used now.
  - Blobs of pending and local-only (`noSync`) records are never deleted, also the pending uploads of another account. Blobs of records deleted with `cacheOnly` (local-only tombstones) can be deleted. When the pinned blobs alone keep the cache above the limit, eviction pauses until the cache grows by 10% of the limit or a sync pass ends.
  - A file larger than 90% of the limit is returned but not cached: downloads, and the copies of uploads that the server accepted. Unsynced uploads are always stored. `client.fitsFileCache(bytes)` tells if a file of that size goes into the cache.
  - Only blobs written through `client.db.setFile` (all package writes) take part in the limit. A blob inserted into `BlobFiles` with raw SQL has no `BlobFileStats` row: it is not counted and never evicted.
  - `runMaintenance()` applies the limit and returns up to 4096 free pages (about 16 MB) to the file system with `PRAGMA incremental_vacuum`. It does this also when the TTL is `null` (it was a no-op then). It never runs a full `VACUUM`.
  - New databases use `auto_vacuum = INCREMENTAL`. A database created before 0.7.0 gets smaller only with `client.db.compact(full: true)`: a full `VACUUM` that can take seconds and needs free disk space of about the database size.
  - `expireAfter` keeps its meaning: it sets freshness. An expired copy is downloaded again when the server is reachable and is still used offline, until `runMaintenance()` with a TTL deletes it (as before). The size limit is the retention control.
  - Schema: the v3 → v4 migration adds the table `BlobFileStats (fileId, size, lastAccess)` with the index `idx_blob_file_stats_access (lastAccess, size)` and the trigger `blob_files_delete`, which deletes the stats row of a deleted blob. `BlobFiles` is unchanged from 0.6.0. The upgrade does not rewrite the cached blobs: it reads only their sizes (time proportional to the number of rows, not the bytes). Blobs cached before the upgrade have no `lastAccess` and are evicted first.
  - Native connections set `PRAGMA journal_size_limit` to 8 MB, so a large write does not leave a large WAL file.
- **`DataBase.setFile` returns `Future<void>`.** It returned the inserted `BlobFile`, which copied the blob back from the database isolate. Read the blob with `client.db.getFile(recordId, filename)` when you need it.

### New

- **`requestTimeout`.** `$PocketBase(requestTimeout:)` and `$PocketBase.database(requestTimeout:)`, default 15 s. It limits single-record reads and writes without file uploads. When it elapses, offline-first writes are queued and reads fall back to the cache. `null` disables the limit.
- **`client.syncPendingChanges({includeFailed})`.** One sync pass at a time: a call during a pass returns a future that completes after one more pass. It runs automatically at startup, when the server becomes reachable, on app resume and after login. It never throws. Collections sync parents first (by relation fields), records oldest first (`cachedAt`). `client.syncCompleted` always completes.
- **`client.syncFailures`.** A `Stream<SyncFailure>` with `collection`, `recordId`, `operation` (`SyncOperation.create`, `update`, `delete`), `error`, `statusCode` and `dropped`.
- **`client.discardPendingChange(collection, id)`.** Removes a pending local change. The next read loads the server's version.
- **`client.db.pendingRecords({service})`.** A `Selectable<Service>` of the pending rows. Use `.watch()` for a live queue. It excludes local-only rows and rows of other accounts, and includes parked rows (`syncError`). `db.pendingServices()` lists the collections that automatic sync will push. `$RecordService.pending()` uses `pendingRecords`.
- **`RecordMeta` (exported).** Names of the row bookkeeping keys: `synced`, `isNew`, `deleted`, `noSync`, `retryCount`, `pendingFields`, `pendingFiles`, `pendingOwner`, `pendingRev`, `syncError`, `pendingBase`, `baseUpdated`, `pendingDeltas`. Helpers `flag`, `isPending` and `strip`. `DeltaKind` (exported) names the values of `pendingDeltas`: `number`, `append`, `prepend`, `remove`. New `pbTimestamp()` formats a time like PocketBase.
- **`$RecordService.pushPending(id)`.** Pushes one pending record and returns a `PushOutcome` (`synced`, `skipped`, `retryLater`, `rejected`).
- **`getFirstListItemOrNull(filter)`.** Returns `null` when no record matches.
- **`connectivity.canReachServer` and `connectivity.probeSoon()`.** `canReachServer` is `true` when a network interface is up and the server is not known to be down.
- **`db.clearCache({keepPending = true})`.** Deletes cached data, responses and blobs. It keeps the schema and, by default, the pending changes.
- **`PocketBaseImageProvider(thumb:, timeout:)`.** The constructor is `const`. Decode size: with `pixelWidth`/`pixelHeight`, the smallest size that covers the box and keeps the aspect ratio, never enlarged. Else `size` × device pixel ratio. Else the full size.
- **`$FileService.getFileBytes(thumb:, timeout:)`.** Concurrent requests for the same file and thumb share one download. `client.files` is one instance per client.
- **`maxFileCacheBytes` and the file cache API.** See "Size-limited file cache" in Breaking changes. `client.enforceFileCacheLimit()` applies the limit now (the package calls it after each blob write). `client.fitsFileCache(bytes)` returns `true` when a file of that size goes into the cache (at most 90% of the limit, or no limit). `client.db.fileCacheBytes()` returns the cache size (the sum of `BlobFileStats.size`). `client.db.evictFiles(maxBytes:, targetBytes:)` deletes unpinned blobs (larger than the target first, then least recently used) and returns `(count, bytes, remaining)`. `client.db.touchFile(id)` marks a blob as used now. `client.db.compact({maxPages = 4096, full = false})` returns free pages to the file system and returns the number of pages released. `MaintenanceResult.evictedFiles` and `evictedBytes` count the blobs that maintenance deleted for the limit; `totalDeleted` includes `evictedFiles`. `deletedFiles` counts the expired blobs and the blobs of records that are no longer cached.

### Fixes

- **Performance.** The database runs in a background isolate. New indexes on `services.service` and on blob `(recordId, filename)`. Expand is resolved for the whole result with one query per relation field and level (it was N+1 per row and re-read every schema). Schema definitions are cached in memory. The FTS trigger re-indexes only when the record JSON changes.
- **Performance: record watchers re-run only for their collections.** `watchRecord(s)`, `watchRecord(s)State` and `client.db.$query(...).watch()` re-run only for writes to their own collection, to the collections they expand, and (with `expand`) for schema changes. Before, every write to any collection re-ran every watcher: 1000 writes to another collection with 20 open watchers caused 20,000 re-runs, now none. `pendingRecords().watch()`, `search(...).watch()` and app queries with `customSelect(readsFrom: {client.db.services})` still re-run on every write to `services`. Raw SQL writes reach record watchers only when drift is told: use `customUpdate(..., updates: {client.db.services})`, or call `client.db.markTablesUpdated({client.db.services})` after `customStatement` (`customStatement` alone notifies nothing, as before).
- **Shared realtime subscriptions.** All live queries of a collection topic share one realtime subscription. Each server event is written to the cache once (it was once per watcher).
- **Refetch after reconnect.** Live queries refetch after a realtime reconnect (`PB_CONNECT`) and when the server becomes reachable. Changes made while disconnected are not missed.
- **Pending edits survive refreshes.** List refreshes and realtime events do not overwrite a pending offline edit: the locally changed fields win until they are synced. A realtime delete keeps a row with pending edits; sync reports the conflict.
- **`fields:` projections.** Projected results only merge into existing cached rows. They never replace rows or insert incomplete rows.
- **Offline `getList` totals.** `totalItems` respects the filter.
- **`cacheFirst` cold cache.** `getOne` with an empty cache waits for the server instead of throwing.
- **`setSchema` race.** Reads and writes wait for a pending `setSchema`. An un-awaited `..setSchema(...)` no longer races the first write.
- **No uncaught errors.** Realtime events for collections missing from the local schema are logged. Bad filters in `watch*State` are delivered as stream errors and as `QueryState.error`.
- **Connectivity accounting.** Only connectivity failures (status 0, timeouts, 502, 503, 504) count towards "offline". Any server answer marks the server reachable. `getFirstListItem` now reports failures too.
- **Timestamps.** Local timestamps have millisecond precision in the PocketBase format.
- **Offline create then delete.** Deleting a record that was created offline and never synced removes it at once. No server delete is queued. When the create is being pushed at that moment, the deletion is queued instead, so the record does not survive on the server.
- **Changes during a push.** Pushes, online writes and batch sends of one record run one at a time; a second push waits and then sends what is still pending, so a file is uploaded once. A change made while the record's push is in flight stays pending: an edit keeps the server's names of the files just uploaded, a file attached meanwhile is still uploaded, a deletion stays a deletion, and a `cacheOnly` change stays local. A rejection does not count against (or report) an edit made during the push. Local writes of a cached record are atomic (database transactions).
- **Online writes win over older queued edits.** An online update (`networkOnly`, `networkFirst`, `cacheAndNetwork`, or a batch update/upsert) of a record with a queued edit removes the fields it set from the queue; only the other queued fields still sync. Exception: an online modifier (`n+: 1`) of a field with a queued modifier edit keeps both changes; an online plain set (`n: 5`) supersedes the queued edit of that field. Online writes wait (at most `requestTimeout`) for a running push of the same record, so they reach the server after it. When the push takes longer (an upload), a `cacheAndNetwork` write is queued behind it; `networkOnly` and `networkFirst` writes throw `ClientException` with status 0. A timed-out push keeps its record locked until its request settles (at most 3 × `requestTimeout` more).
- **Stalled uploads do not block sync.** A sync pass waits at most `requestTimeout` for each record. A slow upload continues in the background and keeps its record locked, but the pass moves on and `syncCompleted` completes.
- **Batch updates and deletes of records created offline.** The batch first pushes the queued creates it references (the server rejects the whole batch when a record does not exist yet). With `cacheAndNetwork`, the batch is queued when such a create cannot be pushed.
- **Pending edits from 0.6.x.** A pending update written by 0.6.x (no `pendingFields`) still syncs the whole record after a new offline edit.
- **`client.close()` closes the package's realtime subscriptions.** The SDK closes the realtime connection when no other subscription is left. Events after `close()` are ignored.
- **Pruning keeps new pending changes.** List refreshes and `limit` window pruning re-check, in the delete transaction, that a row has no pending change.
- **Lost create response.** A create retried after a lost response (the id already exists) becomes an update instead of failing.
- **`$collection()` without collections API access.** It uses the cached schema when the collections API is not accessible (offline, or a regular account).
- **Delete of a record that is not cached is queued.** `delete()` with `cacheAndNetwork` or `cacheFirst` of an id that is not in the cache queues the deletion when the server is unreachable (offline, 503, connection refused, timeout) and, with `cacheFirst`, also when the server is reachable. Before, nothing was sent. The queued deletion is a bare tombstone row: the id and the bookkeeping keys only (`deleted`, `synced: false`, `isNew: false`, `noSync: false`, `pendingRev`, `pendingOwner`). `pendingRecords()` can return such rows: a pending-queue UI must not expect record fields. `writeLocalDelete(sync: true)` (on `DataBase` and `$RecordService`) always returns `true`; it returns `false` only for `sync: false` without a cached row. An offline batch delete of an uncached id returns status 204 (queued), not 404. When the server answers 404 (the record is already gone, or the delete rule does not match), the queued deletion ends without a `SyncFailure`, the same as for cached tombstones.
- **Queued modifier edits sync as deltas.** Offline and `cacheFirst` updates with `n+`/`n-` (numbers) and `f+`/`+f`/`f-` (multi-value relation, select and file fields) sync as modifiers relative to the value they were made on. Numbers send the difference (`n+: 2`; a negative difference as `n-`). Multi-value fields send the added values as `f+` (or `+f`) and the removed values as `f-`. Concurrent increments, appends, removals and file uploads of other devices are kept. Before, the queued edit sent the absolute local value and overwrote them.
  - Last write wins for all other edits: a field with a plain set (`n: 5`, `tags: [...]`) anywhere in its pending history sends its absolute value. This also applies to single-value, JSON and text fields. Pending rows written before this change (no base) send absolute values.
  - New `RecordMeta` keys in the pending row (visible in `RecordModel.data`): `pendingBase` (the server value of each pending field when it first became pending), `baseUpdated` (the server `updated` value then) and `pendingDeltas` (the fields whose every edit was a modifier, with the kind: `number`, `append`, `prepend` or `remove`).
  - Until the change syncs, list refreshes and realtime events do not overwrite the locally changed fields. A realtime delete keeps a row with pending edits; the sync then gets 404, drops the edit and emits `SyncFailure(dropped: true)`.
  - Limits: mixed append and prepend edits are sent as an append. Float differences can have rounding errors.
  - Counters: use `+`/`-` modifiers. Queued modifier edits merge with the changes of other devices; plain sets are last-write-wins.
  - Additive API: `DataBase.completePendingSync(..., sentBody:, partial:)`; `DataBase.applyRequestBody` also returns `deltas`.
- **Batches keep queued changes.** A batch update of a record with an unsynced local change no longer marks the whole change as synced. Fields, increments and uploads that the batch did not send still sync. A value that the batch set is not overwritten later by the older queued value (also with `networkOnly`). An edit made while an online batch is in flight is kept, also when it restores the old value.
- **Sent fields are done.** A field that a batch or a sync push sent is not sent again when the server stores it in another form (dates) or does not return it (the `password` of an auth record). With a `fields:` projection, the cached record keeps its other fields and queued increments are not lost.
- **Open watchers follow an account switch.** After a login with another account, open watchers (`watchRecord(s)`, `$query`, `pendingRecords()`, `search()`) showed the pending changes of the previous account and hid the pending changes of the new account until the caller listened again. They now change to the rows of the new account without a new listen. `@request.auth.id` filters also follow the switch. `$query(...).watch()`, `pendingRecords().watch()` and `search(...).watch()` complete when the database closes.
- **Search ignores the sync bookkeeping.** The full-text index (`text_entries`) leaves out `retryCount`, `pendingFields`, `pendingFiles`, `pendingOwner`, `pendingRev`, `syncError`, `pendingBase`, `baseUpdated` and `pendingDeltas` (`synced`, `isNew`, `deleted` and `noSync` stay). A record with a pending edit is found by its new value, not by its old value in `pendingBase`. The v4 migration re-creates the FTS triggers and re-indexes all records.

### Repo & tooling

- **`example/backend/`.** A Go backend (PocketBase v0.40.6) for the example app, the package tests and the integration suite. It contains the TaskFlow collections, the package test collections (`todo`, `ultimate`, `active_todo`), the lab collections and the `/api/lab/*` fault-injection routes (chaos modes `fail503`, `drop`, `hang`, `latency`; stats; server-side mutations). It seeds the superuser `test@admin.com` for the tests. `test/test-instruction.md` explains how to run it.
- **`test/integration/`.** Regression suite for the review defects, run against the example backend. `dart_test.yaml` runs the test files one at a time.
- **`tool/device_lab/`.** Android profile-mode harness. It measures UI-isolate blocking, the image cache and the probes. It is not part of the package API.
- **`example/android` regenerated.** Gradle 9, AGP 9, Kotlin DSL. The INTERNET permission is in the main manifest. Cleartext HTTP is allowed only in debug and profile builds.
- **Drift 2.35.** `drift: ^2.35.3` and `drift_dev: ^2.35.2`. The generated code uses `$_getPrefetchedDataByColumns`, new in drift 2.35.3.
- **PocketBase Dart SDK 0.25.3.** `pocketbase: ^0.25.3`. SDK 0.25.2 closes the realtime connection after 315 seconds without messages and reconnects (a workaround for network connections that end without notice). The package refreshes its live queries after each reconnect.
- **`PB_URL`.** All server-backed tests read the server address from `PB_URL` (`test/test_server.dart`, default `http://127.0.0.1:8090`).
- **New tests.** `test/services/offline_delete_test.dart`, `test/services/watch_scope_test.dart`, `test/services/delta_sync_test.dart`, `test/files/blob_cache_limit_test.dart` and `test/database_migration_test.dart` (drift `SchemaVerifier`, v2 → v4 and v3 → v4; schema helpers in `test/generated_migrations/`; `drift_schemas/drift_schema_v3.json` added).

## 0.6.0

### Connectivity: Custom Realtime Server Monitor

- **Replaced `internet_connection_checker_plus` with a purpose-built realtime monitor.** The new `ConnectivityService` tracks reachability of *your actual PocketBase server* instead of polling third-party hosts:
  - **Interface events** (`connectivity_plus`): losing the last network interface marks the app offline instantly; regaining one triggers an immediate probe. Works on web (`navigator.onLine`), mobile and desktop.
  - **Server health probes**: a lightweight `GET /api/health` probe is the source of truth. While online a slow keepalive probe runs (`connectivityOnlineProbeInterval`, default 60s); while offline, probes back off exponentially (`connectivityOfflineBackoffMin` 5s doubling to `connectivityOfflineBackoffMax` 60s) so restoration is detected within seconds.
  - **Request outcomes**: successful CRUD requests flip the status online instantly; consecutive failures (2) mark it offline.
  - **Connectivity restoration now always triggers the pending-sync retry.** Previously the "connected" platform event did not flip the status, so queued changes could sit unsynced until an unrelated request happened to succeed.
  - `ConnectivityService` is now a per-client instance (not a singleton) with a `dispose()` — no more leaked 10s check timers in widget tests. The test flag `enableInternetChecker` was renamed to `enableProbes`.

### Sync Engine: Limbo & Tombstone Fixes

- **Fixed offline-delete limbo**: a record created offline and deleted before ever syncing (`isNew: true` + `deleted: true`) made the sync engine attempt a doomed server delete (404) on every sync round forever. It is now purged locally, and server 404s on delete/update retries purge the local copy instead of looping (handles deletions that raced another device).
- **Offline-deleted records no longer appear in local reads.** Tombstoned records (`deleted: true` awaiting server sync) were previously returned by `getFullList`, `getOne`, `watchRecords`, `search` and `$count`, so deletes appeared to "do nothing" in the UI. They are now excluded everywhere while remaining in the pending queue; `client.db.$query(..., includeDeleted: true)` opts back in for internal/diagnostic reads.
- **`mergeLocal` no longer resurrects pending deletes**: a background list fetch landing before the sync engine can no longer overwrite a tombstone with stale server data.
- **`cacheFirst` deletes now queue properly**: the old implementation hard-deleted the local row and fired a best-effort background delete — if that failed (e.g. offline), the deletion was silently lost and the record resurrected on the next fetch. It now writes a syncable tombstone first.

### Housekeeping

- Bumped minimum example/tests to run against a live PocketBase; added regression tests for the limbo purge, tombstone filtering, merge protection, watch-stream removal, and connectivity state machine (probe/backoff/request-signal).

## 0.5.0

### New Features & Examples

- **Modernized Example Application (TaskFlow)** - Replaced legacy example with a feature-first reference app demonstrating offline-first task and project management, Riverpod state management, GoRouter navigation, relation expansion, local full-text search, and live sync diagnostics.
- **Added Skills (`skills/pocketbase-drift/`)** - Added comprehensive, production-grade agent playbook skills and architecture reference guides directly in the repository.

### Web & WASM Improvements

- **Web Database Worker Resolution** - Updated Web WASM connection to directly resolve `drift_worker.js` and `sqlite3.wasm` relative to `Uri.base`, eliminating unnecessary file renaming and URL construction errors in Web Workers.
- **Web Connectivity CORS Guard** - Guarded internet checker execution on web platforms to prevent browser CORS violations on captive portal endpoints.

## 0.4.4

### Improvements & Bug Fixes

- **Stream Error Propagation & Lifecycle Safety** - Resolved an issue where initial fetch failures in `watchRecords`/`watchRecordsState` vanished silently rather than surfacing as stream errors. Closed race-condition subscription leak windows during in-flight cancellations, and added `onPause`/`onResume` support to underlying Drift queries. Special thanks to [@qtpi-bonding-org](https://github.com/qtpi-bonding-org) for identifying and contributing the initial fix for these lifecycle issues.
- **Enhanced `QueryState<T>` Error Handling** - Added `error` and `hasError` properties to `QueryState<T>` so offline-first Flutter UIs (such as `StreamBuilder` and Riverpod `StreamProvider`) can retain and inspect network error states alongside cached data without errors being wiped out by subsequent data events.
- **Deep Relation Equality in `distinctResults`** - Expanded relations (`data['expand']`) are now checked within `distinctResults` so changes to related records properly trigger stream emissions.
- **Analysis & Try-Catch Await** - Resolved an analyzer warning in `getFirstListItemOrNull` by awaiting the future inside the `try` block.

### Dependencies

- **Removed `sqlite3_flutter_libs`** - Removed the obsolete `sqlite3_flutter_libs` package (now end-of-life and unnecessary with `sqlite3` 3.x).
- **Updated Dependencies** - Updated `pocketbase` to `^0.25.0`, `drift` to `^2.34.3`, `sqlite3` to `^3.5.2`, `internet_connection_checker_plus` to `^3.1.1`, and `path_provider` to `^2.1.6`.

## 0.4.3

### Dependencies

- **Updated package dependencies** - Updated core dependencies including `pocketbase`, `sqlite3`, and `internet_connection_checker_plus` to latest versions.

## 0.4.2

### Dependencies

- **Connectivity** - Replaced `connectivity_plus` with `internet_connection_checker_plus` to verify actual internet access rather than just network interface availability.
- **Updated package dependencies** - Bumped `drift` and `drift_dev` to `^2.33.0`, `sqlite3` to `^3.3.1`, and `shared_preferences` to `^2.5.5`.

### Improvements

- **Enhanced `ConnectivityService`** - Now relies on `internet_connection_checker_plus` for verifying real internet access. It maintains an optimistic "online-by-default" approach that defaults to `true` to prevent UI flickering, and falls back rapidly when an actual network request fails.

## 0.4.1

### New Features

- **Network Fetching State for Streams** - Introduced `QueryState<T>` wrapper and two new methods `watchRecordsState` and `watchRecordState`. This allows offline-first apps to distinguish between an "empty cache while fetching data" and a "truly empty database result", enabling them to show loading indicators during initial network requests instead of instantly flashing empty states.

### Improvements

- **Stream Performance Optimization (Distinct Results)** - Added a `distinctResults` parameter (enabled by default) to `watchRecord`, `watchRecords`, `watchRecordState`, and `watchRecordsState` ([#13](https://github.com/DrDejaVuNG/pocketbase_drift/issues/13)). This prevents huge, unnecessary Riverpod/Stream rebuild fan-outs by natively suppressing stream emissions when a SQLite cache update does not actually change the underlying query's effective result set (validated elegantly using `id` + `updated` fields).

### Bug Fixes

- **Local Modification Timestamps** - Fixed an issue where offline mutations via `$update` failed to automatically bump the local `updated` property. Local modifications now cleanly generate a new UTC timestamp if one isn't explicitly provided, ensuring cache invalidations and UI streams work smoothly.
- **Strict UTC Standardization** - Fixed and standardized all internally generated timestamps (cache TTLs, expiration dates, schema insertions, local creations, and file caches) to strictly use `DateTime.now().toUtc()`. This ensures absolute compatibility with PocketBase's ISO8601 UTC server expectations and prevents time-zone drift synchronization anomalies.

## 0.4.0

**BREAKING CHANGES**: Method names have been updated for consistency and clarity.

### Breaking Changes

- **Renamed `cacheSchema` to `setSchema`**: The method used to provide the JSON database schema to the client has been renamed. Change `client.cacheSchema(schema)` to `client.setSchema(schema)`.
- **Renamed `getFileData` to `getFileBytes`**: The method in the `files` service to retrieve file bytes directly has been renamed. Change `client.files.getFileData(...)` to `client.files.getFileBytes(...)`.

## 0.3.17

### Dependencies

- **Updated package dependencies** - Updated core dependencies including `drift`, `sqlite3`, and others.

## 0.3.16

### Bug Fixes

- **Fixed realtime subscriptions interfering with each other ([#12](https://github.com/DrDejaVuNG/pocketbase_drift/issues/12))** - Resolved an issue where multiple `watchRecords` or `watchRecord` streams subscribed to the same collection would break each other's realtime updates. When one stream was cancelled (e.g., navigating away from a tab), it called `unsubscribe('*')` which removed **all** listeners for that topic — including those belonging to other active streams. The fix stores the targeted `UnsubscribeFunc` returned by `subscribe()` and calls that on cancel instead, ensuring only the specific listener is removed while leaving other subscriptions intact.

## 0.3.15

### New Features

- **Configurable Sync Retry Count** - Added `localSyncRetryCount` parameter to `$PocketBase` and `$PocketBase.database` (default: 5). This allows developers to control how many times a record update/create should be retried before being considered permanently failed.

### Bug Fixes

- **Robust Handling of Stuck Records ([#10](https://github.com/DrDejaVuNG/pocketbase_drift/issues/10))** - Resolved an issue where records suffering from validation errors (including "orphaned" records referencing deleted parents) would retry indefinitely, causing battery drain and blocking the sync queue.
  - All `400 Bad Request` errors (validation failures, orphans, etc.) now increment a retry counter on the local record.
  - Once the `localSyncRetryCount` is exceeded, the local record is automatically deleted to unblock the sync queue.
  - Useful for cleaning up local state that has become invalid relative to the server (e.g., a local comment on a post that was deleted on the server).

## 0.3.14

### Bug Fixes

- **Fixed `clearAllData()` also clearing the schema cache** - The `clearAllData()` method was incorrectly deleting all records from the `services` table, including the cached collection schema (stored with `service = 'schema'`). This caused issues when the app tried to use schema-dependent features after clearing user data. The method now preserves schema records while clearing all other data.

- **Improved connectivity restoration detection** - The `connectivity_plus` package doesn't reliably detect when network connectivity is restored, especially on iOS Simulator. The connectivity service now uses a hybrid approach:
  - **Platform detection**: Uses `connectivity_plus` for detecting when the device goes offline
  - **Request-based detection**: Network request success/failure is now reported to the connectivity service
  - When a network request succeeds after being marked offline, connectivity is immediately restored
  - After 2 consecutive network failures, the device is marked as offline
  - Explicit `checkConnectivity()` calls (e.g., on app resume) trust the platform status directly

### Improvements

- Added `shouldAttemptNetwork` getter to `ConnectivityService` - Returns `true` if the platform reports a network interface is available, regardless of recent request success. Use this for deciding whether to TRY a network request. Use `isConnected` for UI display or pessimistic decisions.
- Added `reportNetworkSuccess()` and `reportNetworkFailure()` methods to `ConnectivityService` for request-based connectivity tracking
- All network request decisions now use `shouldAttemptNetwork` instead of `isConnected`, allowing the app to discover connectivity restoration by actually trying requests when the platform reports a network interface is available

## 0.3.13

### Bug Fixes

- **Fixed file field names being null when saving offline** - Resolved a critical issue where creating or updating a record with files while offline (using `cacheAndNetwork` policy) would result in file field names being saved as `null` or empty in the local database. The `_prepareCacheOnlyBody()` method is now called before network attempts, ensuring file field names and blobs are properly cached regardless of network availability.

- **Fixed files not syncing to server on connectivity restore** - Files attached to records created offline were not being uploaded when connectivity was restored and `retryLocal()` ran. The sync mechanism now:
  - Retrieves cached file blobs from the local database
  - Identifies file fields from the collection schema
  - Includes files as `MultipartFile` attachments when syncing pending creates/updates to the server
  - Added `getFilesForRecord()` method to the database for retrieving all cached files for a record

- **Improved file retrieval fallback behavior** - File retrieval now follows the "stale data is better than no data" principle for offline-first apps:
  - `cacheOnly` with expired cache: Now returns the expired cached file instead of throwing
  - `cacheAndNetwork` with expired cache + network failure: Now falls back to returning the expired cached file instead of throwing a network error
  - `cacheOnly` with no cache: Now throws a descriptive error message
  - Added informative logging for cache expiration and fallback scenarios

### Tests

- Added 3 new tests for offline file creation with network failure simulation
- Added 1 test for file sync on connectivity restore
- Added 3 tests for file retrieval fallback behavior

## 0.3.12

### New Features

- **Global Request Policy** - Added a `requestPolicy` parameter to the `$PocketBase` client that sets a default policy for all service methods. This allows you to configure the offline-first behavior globally instead of passing it to every method call.
  - Defaults to `RequestPolicy.cacheAndNetwork`
  - Can be overridden per-call by passing an explicit `requestPolicy` to any method
  - All method `requestPolicy` parameters are now nullable (omit to use the global default)

### Bug Fixes

- **Fixed duplicate record creation with realtime subscriptions** - Resolved a critical issue where creating a record with `RequestPolicy.cacheAndNetwork` while using `watchRecords()` or other realtime subscriptions could result in duplicate records being created locally. This occurred when PocketBase ignored/replaced the client-provided ID (e.g., due to custom hooks) and generated its own ID. The code now detects ID mismatches between the sent and received ID, and uses the server's ID to prevent duplicates.
  - Added ID mismatch detection in `_createCacheAndNetwork` 
  - Added ID mismatch handling in `_tryCreateOnServer` for background sync
  - A warning is now logged when the server doesn't use the provided ID

## 0.3.11

### Bug Fixes

- **Fixed single-select validation and expansion** - Resolved an issue where `select`, `file`, and `relation` fields were incorrectly treated as multi-select (lists) when their `maxSelect` schema option was set to `0` or `null`. Per PocketBase documentation, `maxSelect <= 1` (including 0/null) indicates a single value (String), while `maxSelect >= 2` indicates multiple values (List). This fix ensures that fields with default or explicit 0/1 `maxSelect` are correctly validated and returned as single strings, preventing "Field must be a list" errors.

### Dependencies

- **Updated `pocketbase` to v0.23.1** - Includes a fix for the "all-in-one" OAuth2 flow that prevented successful re-authentication after a failed attempt.

## 0.3.10

### New Features

- **Enhanced Filter Parser** - Major improvements to the filter parser for better PocketBase compatibility and new operators:

  **Literal Type Support:**
  - `null` literal - `field = null` now correctly translates to `IS NULL` in SQLite
  - Boolean literals - `field = true` and `field = false` are now supported
  - Numeric literals - Unquoted numbers like `score > 100` or `price = 19.99` are handled correctly

  **"Any-of" Operators for Multi-Value Fields:**
  - `?=`, `?!=` - Any element equals/not equals
  - `?>`, `?>=`, `?<`, `?<=` - Any element comparison
  - `?~`, `?!~` - Any element LIKE/NOT LIKE
  - Example: `tags ?= "flutter"` checks if any tag equals "flutter"

  **DateTime Macros:**
  - `@now` - Current UTC datetime
  - `@todayStart`, `@todayEnd` - Day boundaries
  - `@yesterday`, `@tomorrow` - Relative dates
  - `@monthStart`, `@monthEnd`, `@yearStart`, `@yearEnd` - Period boundaries
  - `@second`, `@minute`, `@hour`, `@day`, `@weekday`, `@month`, `@year` - Time components
  - Example: `created >= @todayStart && created <= @todayEnd`

  **Field Modifiers:**
  - `:lower` - Case-insensitive comparison using `LOWER()`
  - `:length` - Array length check using `json_array_length()`
  - Example: `name:lower = "john"` or `tags:length > 2`

  **Comment Stripping:**
  - Single-line comments (`// comment`) are now stripped before parsing

### Bug Fixes

- **Fixed date format mismatch causing incorrect sorting** - Resolved an issue where records stored via `setLocal` and `mergeLocal` (used by realtime subscriptions and batch syncs) would have their `created`/`updated` timestamps re-formatted, replacing the ISO 8601 `T` separator with a space. This caused string-based sorting to produce incorrect results when mixed with records stored via `$create` which preserved the original format. All methods now preserve the original timestamp format from the server. ([#8](https://github.com/DrDejaVuNG/pocketbase_drift/issues/8))

### Improvements

- **Comprehensive test suite** - Added 49 new tests covering all filter parser features

## 0.3.9

### New Features

- **Batch Requests with Offline Support** - Added `$createBatch()` method for executing transactional batch operations with full offline-first support.
  - Queue multiple create, update, delete, and upsert operations across collections
  - Execute all operations in a single HTTP request to PocketBase
  - Full `RequestPolicy` support for controlling online/offline behavior
  - When offline or on failure with `cacheAndNetwork`, operations are stored locally and retried as individual operations when connectivity is restored

## 0.3.8

### New Features

- **Nullable Cache TTL** - The `cacheTtl` parameter in `$PocketBase.database()` is now nullable. Setting it to `null` disables automatic cache cleanup, allowing data to be persisted indefinitely.
- **Configurable Logout Cleanup** - Added `clearOnLogout` parameter to `$AuthStore` (default: `true`). Developers can now set this to `false` to preserve local data when the user logs out, improving the experience for offline-first applications where re-fetching data might be expensive.

### Bug Fixes

- **Fixed Connectivity & Cache Issues on Re-login** - Resolved a critical issue where logging out and back in would cause connectivity to report incorrectly and cached streams to stop responding.
  - `ConnectivityService` is now a true singleton that is never disposed, matching the behavior of `connectivity_plus`'s global `Connectivity()` singleton. This prevents instability when recreating client instances.
  - Simplified database connection by removing manual isolate spawning, using Drift's built-in connection handling instead.
  - **Note for developers**: If using Riverpod, invalidate your `pocketBaseProvider` after logout to ensure all dependent providers are refreshed with the new client instance.

## 0.3.7

### Bug Fixes

- **Fixed nested expanded records not being cached** - When fetching records with nested expand, the related records are now automatically cached to their respective collection tables. This enables local expand to work correctly when those collections are later queried independently.
  - Previously, `mergeLocal` (used by `getFullList`) bypassed the caching logic, causing expanded records to be missing from the local cache.
  - The fix also applies recursively, so deeply nested expands are properly cached at all levels.

### Tests

- Added `expand_cache_test.dart` with 4 tests validating nested expanded record caching behavior.

## 0.3.6

**BREAKING CHANGE**: Local relation expansion now matches PocketBase SDK behavior.

### Breaking Changes

- **Single relations now return objects directly** - Previously, all expanded relations were wrapped in a list, requiring index access (e.g., `expand.author.0.name`). Now, single relations (`maxSelect == 1`) return the object directly, matching the official PocketBase SDK behavior:
  - **Before**: `record.get<String>('expand.author.0.name')`
  - **After**: `record.get<String>('expand.author.name')`
  - Multi relations (`maxSelect > 1`) still return lists and require index access

### Migration Guide

If you were accessing single relation expands with `.0` index, remove the index:

```dart
// Before (0.3.5 and earlier)
final authorName = post.get<String>('expand.author.0.name');
final author = post.get<RecordModel>('expand.author.0');

// After (0.3.6+)
final authorName = post.get<String>('expand.author.name');
final author = post.get<RecordModel>('expand.author');
```

Multi-relation access remains unchanged:
```dart
final firstTag = post.get<String>('expand.tags.0.name');  // Still uses index
```

## 0.3.5

### Documentation

- **Expanding Relations Guide** - Added comprehensive documentation for accessing expanded relations using the PocketBase SDK's `record.get<T>()` dot-notation path syntax (e.g., `record.get<String>('expand.author.0.name')`). Covers basic expansion, nested (multi-level) expansion, and multi-relation access patterns.

- **Advanced: Direct Database Access** - Added new documentation section explaining how to access the underlying Drift database directly via `client.db` for advanced use cases:
  - Database schema overview (tables, columns, primary keys)
  - Running raw SQL queries with `customSelect`
  - Joining data across collections
  - Reactive streams with raw SQL using `.watch()`
  - Executing raw statements with `customStatement`
  - Using the built-in `$query` method

### Tests

- Added `expand_dot_notation_test.dart` with 8 comprehensive tests validating that locally expanded relations work correctly with the PocketBase SDK's dot-notation path access API.

## 0.3.4

### New Features

- **Cache TTL & Expiration** - Added configurable time-to-live (TTL) for cached data. Old synced records and cached responses are automatically cleaned up when `runMaintenance()` is called.
  - Configurable `cacheTtl` parameter in `$PocketBase.database()` (default: 60 days)
  - New `runMaintenance()` method to clean up expired cache data
  - Returns `MaintenanceResult` with counts of deleted items
  - Only removes synced data - unsynced local changes are always preserved
  - Cleans up expired file blobs automatically

## 0.3.3

### New Features

- **Filter-aware sync for deleted records** - Added `syncLocal` method that intelligently syncs deletions from the server to local cache. When fetching data with `getFullList`, the system now detects and removes records that were deleted on the server while offline, even when using filtered queries. This ensures local cache stays in sync with server state.
  - Works with both filtered and unfiltered queries
  - Only deletes records within the filter scope
  - Preserves unsynced local changes, local-only records, and pending deletions
  - Includes safety check to prevent mass deletion on server errors

### Improvements

- **Enhanced `getFullList` behavior** - Now automatically calls `syncLocal` after fetching all pages, ensuring deleted records are cleaned up from local cache
- **Added comprehensive test coverage** - New test suite (`sync_local_test.dart`) with 7 tests covering all edge cases for filter-aware deletion
- **PocketBase-compatible ID generation** - Local IDs are now generated using PocketBase's exact format (`[a-z0-9]{15}`). This eliminates the need for ID remapping during sync, simplifying the offline-first flow:
  - Records created offline now sync with the same ID they were created with
  - Removed `shortid` dependency in favor of a built-in secure random generator
  - Exported `newId()` function for use by consuming applications

### Bug Fixes

- **Fixed partial update validation for offline scenarios** - Partial updates now correctly merge with existing record data before validation, allowing updates with only changed fields when using `cacheFirst` or `cacheOnly` policies
- **Fixed SQLite quote semantics in filters** - Added automatic quote normalization in filter parser to convert double quotes to single quotes for string literals, preventing SQLite from misinterpreting values as identifiers. Both `'id = "$id"'` and `"id = '$id'"` now produce correct SQL


## 0.3.2

### Bug Fixes

- **Critical: Fixed pending sync execution on app restart** - Resolved a critical issue where pending changes would not sync when the app was completely closed and reopened. The sync mechanism now queries the database to identify services with pending records instead of relying on an in-memory cache that gets cleared on app restart. This ensures that all offline changes are reliably synced when connectivity is restored, even after a complete app restart.

## 0.3.1

- Resolved pub.dev issue

## 0.3.0

**BREAKING CHANGES**: Added new `RequestPolicy` options for more explicit control over caching and network behavior.

### New Features

- **New RequestPolicy options**: Added `RequestPolicy.cacheFirst` and `RequestPolicy.networkFirst` for more explicit control over data fetching and synchronization behavior
  - `cacheFirst`: Returns cache immediately, fetches network in background to update cache
  - `networkFirst`: Tries network first, falls back to cache on failure (replaces old `cacheAndNetwork` behavior for reads)
  - `cacheAndNetwork`: Now has distinct behavior - for reads it behaves like `networkFirst`, but for writes it provides resilient offline-first synchronization with automatic retry

### Improvements

- **Refactored write operations** (create/update/delete): Split monolithic methods into smaller, policy-specific implementations for better maintainability
- **Enhanced documentation**: Comprehensive guide on choosing the right `RequestPolicy` for different scenarios
- **Better error messages**: More descriptive error messages that indicate which policy was used when operations fail

### Write Operation Behavior Changes

- **`networkFirst` (new strict mode)**: Writes to server first, updates cache on success, throws error on failure (NO cache fallback)
- **`cacheFirst` (new optimistic mode)**: Writes to cache first, attempts server sync in background
- **`cacheAndNetwork` (enhanced)**: Tries server first, falls back to cache with pending sync on failure (maintains backward compatibility for offline-first apps)

### Migration Guide

**Existing code continues to work** - the default `RequestPolicy.cacheAndNetwork` maintains backward compatibility for most use cases.

However, if you were relying on specific behavior:
- If you want strict server-first writes with no offline fallback, use `RequestPolicy.networkFirst`
- If you want instant UI feedback with background sync, use `RequestPolicy.cacheFirst`
- If you want resilient offline-first behavior (old default), continue using `RequestPolicy.cacheAndNetwork`

## 0.2.1

Exclude certain API paths from caching in `send` method

- Add a list of non-cacheable path segments to exclude specific API endpoints from being cached.
- Modify the send method to bypass cache if the request path contains any of these segments.

This prevents caching sensitive or system data like backups, settings, and logs.

## 0.2.0

Refactor file download methods to use consistent getFileData & Implement auto-generation of file token

- Change token parameter from bool to String?
- Add autoGenerateToken parameter to automatically generate tokens when needed
- Refactor file download methods to use consistent getFileData API across platforms
- Improve file service architecture to better handle token-based file downloads

## 0.1.2

* Update Documentation.

## 0.1.1

* Resolve pub.dev score issues e.g outdated plugin dependencies.

## 0.1.0

*   **Initial release.**

This is the first version of `pocketbase_drift`, a powerful offline-first client for the PocketBase backend, built on top of the reactive persistence library [Drift](https://drift.simonbinder.eu).

### Features

*   **Offline-First Architecture**: Read, create, update, and delete records even without a network connection. The client seamlessly uses the local database as the source of truth.
*   **Automatic Synchronization**: Changes made while offline are automatically queued and retried when network connectivity is restored.
*   **Reactive Data & UI**: Build reactive user interfaces with streams that automatically update when underlying data changes, whether from a server push or a local mutation.
*   **Local Caching with Drift**: All collections and records are cached in a local SQLite database, providing fast, offline access to your data.
*   **Powerful Local Querying**: Full support for local querying, mirroring the PocketBase API. This includes:
    *   **Filtering**: Complex `filter` strings are parsed into SQLite `WHERE` clauses.
    *   **Sorting**: Sort results by any field with `sort` (e.g., `-created,name`).
    *   **Field Selection**: Limit the returned fields with `fields` for improved performance.
    *   **Pagination**: `limit` and `offset` are fully supported for local data.
*   **Relation Expansion**: Support for expanding single and multi-level relations (e.g., `post.author`) directly from the local cache.
*   **Full-Text Search**: Integrated Full-Text Search (FTS5) for performing fast, local searches across all your cached record data.
*   **Authentication Persistence**: User and admin authentication state is persisted locally using `shared_preferences`, keeping users logged in across app sessions.
*   **Cross-Platform Support**: Works across all Flutter-supported platforms, including mobile (iOS, Android), web, and desktop (macOS, Windows, Linux).
*   **Basic File & Image Caching**: Includes a `PocketBaseImageProvider` that caches images in the local database for offline display.
*   **Custom API Route Caching**: Added support for offline caching of custom API routes accessed via the `send` method. This allows `GET` requests to custom endpoints to be cached and available offline, improving performance and reliability for custom integrations.
*   **Robust & Performant**: Includes optimizations for batching queries and file streaming on all platforms to handle large files efficiently.

### Improvements

*   Improved maintainability by refactoring the large `create` and `update` methods in the internal `ServiceMixin` into smaller, more manageable helper methods.
*   Improved web performance by switching from a full `http.get()` to a streaming download for file fetching, aligning it with the more memory-efficient native implementation.