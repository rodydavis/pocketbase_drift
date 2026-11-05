import 'package:drift/drift.dart' show OrderingTerm;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase_drift/pocketbase_drift.dart';

import 'generated_migrations/schema.dart';

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

  test('v3 -> v4 keeps blobs and records their size and last access', () async {
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
    final before = DateTime.now().subtract(const Duration(seconds: 1));

    final db = DataBase(schema.newConnection());
    addTearDown(db.close);
    final blobs = await (db.select(db.blobFiles)
          ..orderBy([(t) => OrderingTerm.asc(t.id)]))
        .get();

    expect([for (final b in blobs) b.size], [12345, 678]);
    expect([for (final b in blobs) b.data.length], [12345, 678]);
    for (final b in blobs) {
      expect(b.lastAccess, isNotNull);
      expect(b.lastAccess!.isAfter(before), isTrue);
    }
    expect(await db.fileCacheBytes(), 12345 + 678);
  });
}
