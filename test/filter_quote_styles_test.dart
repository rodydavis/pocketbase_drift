import 'dart:convert';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase_drift/pocketbase_drift.dart';

import 'test_data/collections.json.dart';

/// Test to verify that both quote styles work correctly in filters
/// This addresses the issue where 'id = "$id"' might cause JSON extract errors
/// compared to "id = '$id'"
void main() {
  final connection = DatabaseConnection(NativeDatabase.memory());
  final db = DataBase(connection);
  final collections = [...offlineCollections]
      .map((e) => CollectionModel.fromJson(jsonDecode(jsonEncode(e))))
      .toList();

  setUpAll(() async {
    await db.setSchema(collections.map((e) => e.toJson()).toList());
  });

  tearDown(() async {
    await db.deleteAll('todo');
  });

  group('Filter Quote Style Tests', () {
    test('Single quotes outside, double quotes inside: \'id = "\$id"\'',
        () async {
      // Create a test record
      final created = await db.$create('todo', {'name': 'test_item'});
      final testId = created['id'];

      // Test with single quotes outside, double quotes inside
      final singleOutside =
          await db.$query('todo', filter: 'id = "$testId"', limit: 1).get();

      expect(singleOutside.length, 1);
      expect(singleOutside.first['id'], testId);
      expect(singleOutside.first['name'], 'test_item');
    });

    test('Double quotes outside, single quotes inside: "id = \'\$id\'"',
        () async {
      // Create a test record
      final created = await db.$create('todo', {'name': 'test_item_2'});
      final testId = created['id'];

      // Test with double quotes outside, single quotes inside
      final doubleOutside =
          await db.$query('todo', filter: "id = '$testId'", limit: 1).get();

      expect(doubleOutside.length, 1);
      expect(doubleOutside.first['id'], testId);
      expect(doubleOutside.first['name'], 'test_item_2');
    });

    test('Both styles should work identically', () async {
      // Create a test record
      final created = await db.$create('todo', {'name': 'test_comparison'});
      final testId = created['id'];

      // Test both styles
      final singleStyle =
          await db.$query('todo', filter: 'id = "$testId"', limit: 1).get();
      final doubleStyle =
          await db.$query('todo', filter: "id = '$testId'", limit: 1).get();

      // Both should return the same record
      expect(singleStyle.length, 1);
      expect(doubleStyle.length, 1);
      expect(singleStyle.first['id'], doubleStyle.first['id']);
      expect(singleStyle.first['name'], doubleStyle.first['name']);
    });

    test('Test with JSON field (non-base field) - single quotes outside',
        () async {
      await db.$create('todo', {'name': 'json_field_test'});

      // 'name' is a JSON field, should use json_extract
      // Using single quotes outside
      final result = await db
          .$query('todo', filter: 'name = "json_field_test"', limit: 1)
          .get();

      expect(result.length, 1);
      expect(result.first['name'], 'json_field_test');
    });

    test('Test with JSON field (non-base field) - double quotes outside',
        () async {
      await db.$create('todo', {'name': 'json_field_test_2'});

      // 'name' is a JSON field, should use json_extract
      // Using double quotes outside
      final result = await db
          .$query('todo', filter: "name = 'json_field_test_2'", limit: 1)
          .get();

      expect(result.length, 1);
      expect(result.first['name'], 'json_field_test_2');
    });

    test('Verify query builder normalizes both styles to single quotes', () {
      final testId = 'abc123';

      // Test both quote styles in queryBuilder
      final (sql1, vars1) = db.queryBuilder('todo', filter: 'id = "$testId"');
      final (sql2, vars2) = db.queryBuilder('todo', filter: "id = '$testId'");

      // Both should generate valid SQL
      expect(sql1, contains('WHERE service = ?'));
      expect(sql2, contains('WHERE service = ?'));

      // IMPORTANT: Both should now produce single quotes (normalized)
      expect(sql1, contains("id = '$testId'"),
          reason:
              'Double quotes in Dart should be normalized to single quotes in SQL');
      expect(sql2, contains("id = '$testId'"),
          reason: 'Single quotes in Dart should remain single quotes in SQL');

      // Verify they produce identical SQL
      expect(sql1, equals(sql2),
          reason: 'Both quote styles should produce identical normalized SQL');
    });

    test('Test with special characters in value', () async {
      // Create a record with special characters
      final created = await db.$create(
          'todo', {'name': "Test with 'single' and \"double\" quotes"});

      // Query using the ID (which shouldn't have special chars)
      final testId = created['id'];

      final result1 =
          await db.$query('todo', filter: 'id = "$testId"', limit: 1).get();
      final result2 =
          await db.$query('todo', filter: "id = '$testId'", limit: 1).get();

      expect(result1.length, 1);
      expect(result2.length, 1);
      expect(result1.first['id'], result2.first['id']);
    });
  });

  group('Filter literals match like PocketBase', () {
    final pb = PocketBase('http://127.0.0.1:8090');

    Future<List<String>> names(String filter) async {
      final rows = await db.$query('todo', filter: filter).get();
      return rows.map((e) => e['name'] as String).toList();
    }

    test('pb.filter-encoded values round-trip with = and ~', () async {
      final values = [
        "it's",
        'say "hi"',
        r'back\slash',
        'line\nbreak',
        'tab\tand\rreturn',
        'unicode é ✓ 😀',
        'snake_case',
      ];
      for (final value in values) {
        await db.$create('todo', {'name': value});
      }
      await db.$create('todo', {'name': 'snakeXcase'});
      await db.$create('todo', {'name': '50%_off'});
      await db.$create('todo', {'name': '50x off'});

      for (final value in values) {
        expect(await names(pb.filter('name = {:v}', {'v': value})), [value],
            reason: value);
        expect(await names(pb.filter('name ~ {:v}', {'v': value})), [value],
            reason: value);
      }

      // As on the server, an unescaped `%` turns the value into a raw LIKE
      // pattern (`_` matches any character)...
      expect(await names(pb.filter('name ~ {:v}', {'v': '50%_off'})),
          unorderedEquals(['50%_off', '50x off']));
      // ...and an escaped one matches literally.
      expect(await names(pb.filter('name ~ {:v}', {'v': r'50\%\_off'})),
          ['50%_off']);
    });

    test('single-quoted literals with escaped quotes match', () async {
      await db.$create('todo', {'name': "O'Brien"});

      expect(await names(r"name = 'O\'Brien'"), ["O'Brien"]);
      expect(await names(r"name ~ 'o\'b'"), ["O'Brien"]);
    });

    test('injection attempts stay literal', () async {
      await db.$create('todo', {'name': 'safe'});
      await db.$create('todo', {'name': "x' OR 1=1 --"});

      expect(await names(r"name = 'x\' OR 1=1 --'"), ["x' OR 1=1 --"]);
      expect(await names('name = "x\' OR 1=1 --"'), ["x' OR 1=1 --"]);
      expect(await names(r'name = "x\" OR 1=1 --"'), isEmpty);
      expect(
          await names('name = "nothing\'); DROP TABLE services; --"'), isEmpty);
      expect(await names('name = "safe"'), ['safe']);
    });

    test('date macros compare against PocketBase-formatted timestamps',
        () async {
      // PocketBase stores dates as `2006-01-02 15:04:05.000Z`.
      String pbDate(DateTime d) =>
          '${d.toUtc().toIso8601String().substring(0, 23)}Z'
              .replaceFirst('T', ' ');
      final now = DateTime.now();

      await db
          .$create('todo', {'name': 'server_today', 'created': pbDate(now)});
      await db.$create('todo', {
        'name': 'server_old',
        'created': pbDate(now.subtract(const Duration(days: 2))),
      });
      await db.$create('todo', {'name': 'local_today'});

      expect(await names('created >= @todayStart'),
          unorderedEquals(['server_today', 'local_today']));
      expect(await names('created < @yesterday'), ['server_old']);
      expect(await names('created <= @now && created > @yesterday'),
          unorderedEquals(['server_today', 'local_today']));
    });

    test('@request.auth.id matches the logged-in account locally', () async {
      await db.$create('todo', {'name': 'mine', 'user': 'account_a'});
      await db.$create('todo', {'name': 'theirs', 'user': 'account_b'});
      addTearDown(() => db.ownerResolver = () => null);

      db.ownerResolver = () => 'account_a';
      expect(await names('user = @request.auth.id'), ['mine']);
      db.ownerResolver = () => null;
      expect(await names('user = @request.auth.id'), isEmpty);
    });

    test('collection macros raise a clear error', () {
      expect(
        () => db.$query('todo', filter: 'owner = @collection.posts.author'),
        throwsA(isA<UnsupportedError>().having(
            (e) => e.message, 'message', contains('@collection.posts.author'))),
      );
    });
  });
}
