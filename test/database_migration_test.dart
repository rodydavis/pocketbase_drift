import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show DatabaseConnection, OrderingTerm;
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase_drift/pocketbase_drift.dart';

import 'generated_migrations/schema.dart';
import 'generated_migrations/schema_v3.dart' as v3;

/// Upgrades of databases written by earlier releases (schemas dumped to
/// `drift_schemas/`; helpers generated with
/// `dart run drift_dev schema generate drift_schemas/ test/generated_migrations/`).
void main() {
  late SchemaVerifier verifier;

  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  for (final from in [2, 3]) {
    test('v$from -> v4 matches a fresh v4 schema', () async {
      final schema = await verifier.schemaAt(from);
      final db = DataBase(schema.newConnection());
      addTearDown(db.close);
      await verifier.migrateAndValidate(db, 4);
    });
  }

  test('v3 -> v4 keeps blobs and records their size; they count as oldest',
      () async {
    final schema = await verifier.schemaAt(3);
    schema.rawDatabase.execute(
      "INSERT INTO Services (id, service, data) VALUES "
      "('r1', 'posts', '{\"id\":\"r1\",\"image\":\"a.jpg\"}')",
    );
    schema.rawDatabase.execute(
      'INSERT INTO BlobFiles (recordId, filename, data, created) VALUES '
      "('r1', 'a.jpg', zeroblob(12345), '2025-01-01T00:00:00.000Z'), "
      "('r1', 'a.jpg?thumb=100x100', zeroblob(678), NULL)",
    );

    final db = DataBase(schema.newConnection());
    addTearDown(db.close);
    final blobs = await (db.select(db.blobFiles)
          ..orderBy([(t) => OrderingTerm.asc(t.id)]))
        .get();
    final stats = await (db.select(db.blobFileStats)
          ..orderBy([(t) => OrderingTerm.asc(t.fileId)]))
        .get();

    expect([for (final b in blobs) b.data.length], [12345, 678]);
    expect([for (final s in stats) s.fileId], [for (final b in blobs) b.id]);
    expect([for (final s in stats) s.size], [12345, 678]);
    expect([for (final s in stats) s.lastAccess], [null, null]);
    expect(await db.fileCacheBytes(), 12345 + 678);

    // A blob cached after the upgrade is younger than both.
    await db.setFile('r2', 'b.jpg', Uint8List(1000));
    final evicted = await db.evictFiles(maxBytes: 1000);
    expect(evicted.count, 2);
    expect([for (final b in await db.select(db.blobFiles).get()) b.recordId],
        ['r2']);
    // The trigger removed the bookkeeping of the evicted blobs.
    expect(await db.select(db.blobFileStats).get(), hasLength(1));
  });

  test('v3 -> v4 does not rewrite the cached blobs', () async {
    final dir = await Directory.systemTemp.createTemp('pbd_migration');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/old.db';
    void wal(dynamic db) => db.execute('PRAGMA journal_mode = WAL;');

    final old = v3.DatabaseAtV3(NativeDatabase(File(path), setup: wal));
    await old.customSelect('SELECT 1').get();
    const count = 64, size = 1024 * 1024;
    for (var i = 0; i < count; i++) {
      await old.customStatement('INSERT INTO Services (id, service, data) '
          "VALUES ('r$i', 'posts', '{}')");
      await old.customStatement('INSERT INTO BlobFiles (recordId, filename, '
          "data) VALUES ('r$i', 'a.jpg', randomblob($size))");
    }
    await old.close();
    final walFile = File('$path-wal');

    final db =
        DataBase(DatabaseConnection(NativeDatabase(File(path), setup: wal)));
    addTearDown(db.close);
    expect(await db.fileCacheBytes(), count * size);

    // Rewriting the blobs would write about 64 MiB to the WAL.
    final walAfter = walFile.existsSync() ? walFile.lengthSync() : 0;
    expect(walAfter, lessThan(size));
  });

  test('v3 -> v4 re-indexes search without the sync bookkeeping', () async {
    final schema = await verifier.schemaAt(3);
    // Indexed by the v3 triggers, bookkeeping included.
    schema.rawDatabase.execute(
      "INSERT INTO Services (id, service, data) VALUES ('r1', 'posts', "
      "'{\"id\":\"r1\",\"title\":\"alpha\",\"synced\":false,"
      "\"syncError\":\"boom\",\"pendingBase\":{\"title\":\"older\"}}')",
    );

    final db = DataBase(schema.newConnection());
    addTearDown(db.close);
    Future<List<String>> hits(String q) async =>
        [for (final r in await db.search(q).get()) r.id];

    expect(await hits('alpha'), ['r1']);
    expect(await hits('boom'), isEmpty);
    expect(await hits('older'), isEmpty);

    // The new triggers remove exactly what was indexed.
    await db.customUpdate(
        "UPDATE services SET data = json_set(data, '\$.title', 'omega') "
        "WHERE id = 'r1'");
    expect(await hits('alpha'), isEmpty);
    expect(await hits('omega'), ['r1']);
    await db.customUpdate("DELETE FROM services WHERE id = 'r1'");
    expect(await hits('omega'), isEmpty);
  });

  test('a first open killed during creation is created again', () async {
    // What a first open of 0.7.0 left when it was killed after
    // `blob_files_delete` (statements ran outside a transaction, and
    // `user_version` was not written yet).
    final schema = await verifier.schemaAt(4);
    final raw = schema.rawDatabase;
    for (final sql in [
      'DROP TABLE CachedResponses',
      'DROP INDEX idx_services_service',
      'DROP INDEX idx_blob_files_record',
      'DROP INDEX idx_blob_file_stats_access',
      'DROP TABLE text_entries',
      'DROP TRIGGER services_insert',
      'DROP TRIGGER services_delete',
      'DROP TRIGGER services_update',
      'PRAGMA user_version = 0',
    ]) {
      raw.execute(sql);
    }

    final db = DataBase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 4);
    expect(raw.select('PRAGMA user_version').single.values.single, 4);

    // Search and the blob cache work.
    await db.customStatement("INSERT INTO Services (id, service, data) "
        "VALUES ('r1', 'posts', '{\"id\":\"r1\",\"title\":\"alpha\"}')");
    expect([for (final r in await db.search('alpha').get()) r.id], ['r1']);
    await db.setFile('r1', 'a.jpg', Uint8List(10));
    expect(await db.fileCacheBytes(), 10);
  });

  test('an interrupted v3 -> v4 upgrade finishes on the next open', () async {
    final v4 = await verifier.schemaAt(4);
    String ddl(String name) => v4.rawDatabase.select(
        'SELECT sql FROM sqlite_master WHERE name = ?',
        [name]).single['sql'] as String;
    final leftover = [
      'ALTER TABLE Services ADD COLUMN "cachedAt" INTEGER NULL',
      ddl('idx_services_service'),
      ddl('idx_blob_files_record'),
      ddl('BlobFileStats'),
      ddl('idx_blob_file_stats_access'),
      ddl('blob_files_delete'),
    ];

    // What an upgrade of 0.7.0 left when it was killed while writing the
    // blob sizes: the v4 objects exist, `user_version` is still 3.
    final schema = await verifier.schemaAt(3);
    final raw = schema.rawDatabase;
    raw.execute(
      'INSERT INTO BlobFiles (recordId, filename, data) VALUES '
      "('r1', 'a.jpg', zeroblob(100)), ('r1', 'b.jpg', zeroblob(200))",
    );
    for (final sql in leftover) {
      raw.execute(sql);
    }
    raw.execute('INSERT INTO BlobFileStats (fileId, size) VALUES (1, 100)');

    final db = DataBase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 4);
    expect(raw.select('PRAGMA user_version').single.values.single, 4);
    expect(await db.fileCacheBytes(), 300);
  });
}
