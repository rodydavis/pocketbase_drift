import 'dart:convert';

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase_drift/pocketbase_drift.dart';

import 'test_data/collections.json.dart';

/// The full-text index holds the record, not the sync bookkeeping that is
/// stored in the same JSON (old values of pending edits, error messages).
void main() {
  late DataBase db;
  const service = 'ultimate';
  const id = 'rec_fts0000001';

  setUp(() async {
    db = DataBase(DatabaseConnection(NativeDatabase.memory()));
    await db.setSchema([...offlineCollections]
        .map((e) => jsonDecode(jsonEncode(e)) as Map<String, dynamic>)
        .toList());
    await db.upsertServerRecords(service, [
      {
        'id': id,
        'collectionName': service,
        'created': '2026-11-04 10:00:00.000Z',
        'updated': '2026-11-04 10:00:00.000Z',
        'plain_text': 'alpha',
      }
    ]);
  });

  tearDown(() => db.close());

  Future<List<String>> hits(String query) async =>
      [for (final r in await db.search(query).get()) r.id];

  test('a pending edit is found by its new value, not by its old one',
      () async {
    await db.writeLocalUpdate(service, id, {'plain_text': 'omega'}, sync: true);
    final row = await db.rowById(service, id);
    expect(row![RecordMeta.pendingBase], {'plain_text': 'alpha'});

    expect(await hits('alpha'), isEmpty);
    expect(await hits('omega'), [id]);
  });

  test('a sync error message is not searchable', () async {
    await db.writeLocalUpdate(service, id, {'plain_text': 'omega'}, sync: true);
    await db.customUpdate("UPDATE services SET data = json_set(data, "
        "'\$.syncError', 'quotaexceeded') WHERE id = '$id'");

    expect(await hits('quotaexceeded'), isEmpty);
    expect(await hits('omega'), [id]);
  });

  test('deleting a row with bookkeeping keeps the index consistent', () async {
    await db.writeLocalUpdate(service, id, {'plain_text': 'omega'}, sync: true);
    await db.customUpdate("DELETE FROM services WHERE id = '$id'");

    expect(await hits('omega'), isEmpty);
    // FTS5 reports a mismatch of index and 'delete' values here.
    await db.customStatement("INSERT INTO text_entries(text_entries, rank) "
        "VALUES ('integrity-check', 0)");
  });
}
