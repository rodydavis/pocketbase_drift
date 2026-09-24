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