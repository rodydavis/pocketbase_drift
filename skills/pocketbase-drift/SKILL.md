---
name: pocketbase-drift
description: Offline-first data architecture using pocketbase_drift with Drift SQLite and Riverpod in Flutter. Covers caching request policies, reactive streams, sync engines, relations, files, and FTS5 search.
license: MIT
---

# PocketBase Drift Sync Playbook

Architecture guide and operational playbook for building **offline-first Flutter apps** backed by PocketBase using the `pocketbase_drift` client and Drift SQLite.

## Core Philosophy & Strategy

1. **Local-First Reads:** The UI always queries and listens to local Drift streams (`watchRecords`) for instant rendering and offline availability.
2. **5 Request Policies:**
   - `cacheFirst`: Return cached data immediately and refresh it in the background. If nothing is cached, wait for the server.
   - `networkFirst`: Try the server first. Use the cache only when the server is unreachable.
   - `cacheAndNetwork` (default): One-time reads work like `networkFirst`. Streams emit the cache immediately, then refresh from the server and follow realtime events. Writes go to the server and queue locally only when the server is unreachable.
   - `cacheOnly`: Read and write the local cache only. Records written with it never sync.
   - `networkOnly`: Bypass the local cache completely. Streams show server data.
3. **Server answers are final:** The cache replaces the server only when the server is unreachable: status 0, timeout, socket error, 408, 429 or 5xx. A 4xx answer (400, 401, 403, 404) is thrown as `ClientException` with the server status. A rejected `cacheAndNetwork` write stores nothing.
4. **Pending Mutation Queue:** Writes made while the server is unreachable (and all `cacheFirst` writes) are stored locally as pending changes. The sync engine (`client.syncPendingChanges()`) sends them when the server is reachable again, parents first and oldest first. An update sends only the changed fields; a field changed only with `+`/`-` modifiers is sent as a delta, so concurrent changes of other devices stay. Use `+`/`-` modifiers for counters. A change that the server rejects `localSyncRetryCount` times is parked, not deleted. Watch `client.syncFailures` to show it to the user.
5. **Logout keeps pending changes:** `authStore.clear()` deletes the cache but keeps unsynced changes of that account. They sync when the same account logs in again. Open streams follow an account switch without a new listen.
6. **An expired session pauses server work:** while `client.hasExpiredSession` is true (token `exp` passed), sync and live-query refreshes pause, cache-policy record reads answer from the cache (a miss throws 401) and `cacheAndNetwork` writes are queued, because PocketBase answers such requests as a guest. A login or `authRefresh` resumes. Listen to `client.onSessionExpired` (and check `hasExpiredSession` at start) to ask the user to log in again.
7. **Riverpod Stream Providers:** Expose reactive queries as `StreamProvider.autoDispose` for automatic lifecycle management and clean UI binding. Create the client before `runApp` and override the client provider with it.

## Reference Index

Detailed implementation guides are located in `references/`:

| Guide | Scope & Focus |
|---|---|
| `references/setup.md` | Dependency installation, client options (`requestTimeout`, `maxFileCacheBytes`), schema caching, widget tests. |
| `references/request-policies.md` | Detailed breakdown and selection guide for the 5 request policies. |
| `references/crud-operations.md` | Offline-safe record creation, updates, deletes, and bulk operations. |
| `references/reactive-streams.md` | `watchRecords` and `watchRecord` stream query patterns. |
| `references/riverpod-integration.md` | Wrapping PocketBase Drift operations in Riverpod providers. |
| `references/sync.md` | Sync engine, triggers and order, partial updates, modifier deltas and conflicts, parked changes (`syncFailures`), connectivity, logout, expired sessions. |
| `references/relations.md` | Relation expansion (`expand`), nested relation caching, and foreign keys. |
| `references/files.md` | Handling file uploads, caching images with `PocketBaseImageProvider`, file cache size limit (`maxFileCacheBytes`). |
| `references/search.md` | Full-text search (FTS5) queries and local indexing. |
| `references/direct-sql.md` | Raw SQL queries, joins, custom Drift DAOs, stream notification of raw writes. |
| `references/maintenance.md` | Cache TTL management, file cache limit, database compaction, diagnostic checks. |
| `references/advanced-patterns.md` | Complex multi-collection transactions and custom sync hooks. |
