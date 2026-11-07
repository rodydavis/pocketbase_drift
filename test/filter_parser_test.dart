import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase_drift/pocketbase_drift.dart';

void main() {
  // Helper function to easily test the parser
  String parseFilter(String filter, {DateTime? now}) {
    final baseFields = {'id', 'created', 'updated', 'service'};
    final parser = FilterParser(filter, baseFields: baseFields, now: now);
    return parser.parse();
  }

  group('Basic Operators', () {
    test('parses equality operator', () {
      final filter = 'name = "test"';
      final expected = "json_extract(services.data, '\$.name') = 'test'";
      expect(parseFilter(filter), expected);
    });

    test('parses not-equal operator', () {
      final filter = 'status != "done"';
      final expected = "json_extract(services.data, '\$.status') != 'done'";
      expect(parseFilter(filter), expected);
    });

    test('parses comparison operators', () {
      expect(
        parseFilter('score > 100'),
        "json_extract(services.data, '\$.score') > 100",
      );
      expect(
        parseFilter('score >= 100'),
        "json_extract(services.data, '\$.score') >= 100",
      );
      expect(
        parseFilter('score < 100'),
        "json_extract(services.data, '\$.score') < 100",
      );
      expect(
        parseFilter('score <= 100'),
        "json_extract(services.data, '\$.score') <= 100",
      );
    });

    test('parses LIKE operator (~)', () {
      final filter = 'name ~ "test"';
      // Should auto-wrap in % for wildcard
      final expected =
          "json_extract(services.data, '\$.name') LIKE '%test%' ESCAPE '\\'";
      expect(parseFilter(filter), expected);
    });

    test('parses NOT LIKE operator (!~)', () {
      final filter = 'name !~ "test"';
      final expected =
          "json_extract(services.data, '\$.name') NOT LIKE '%test%' ESCAPE '\\'";
      expect(parseFilter(filter), expected);
    });

    test('preserves wildcards in LIKE operator', () {
      final filter = 'name ~ "test%"';
      // Should NOT double-wrap since wildcard is present
      final expected =
          "json_extract(services.data, '\$.name') LIKE 'test%' ESCAPE '\\'";
      expect(parseFilter(filter), expected);
    });
  });

  group('Logical Operators', () {
    test('parses logical AND with &&', () {
      final filter = 'name = "test" && status = "active"';
      final expected =
          "json_extract(services.data, '\$.name') = 'test' AND json_extract(services.data, '\$.status') = 'active'";
      expect(parseFilter(filter), expected);
    });

    test('parses logical AND with keyword', () {
      final filter = 'name = "test" AND status = "active"';
      final expected =
          "json_extract(services.data, '\$.name') = 'test' AND json_extract(services.data, '\$.status') = 'active'";
      expect(parseFilter(filter), expected);
    });

    test('parses logical OR with ||', () {
      final filter = 'name = "test" || status = "pending"';
      final expected =
          "json_extract(services.data, '\$.name') = 'test' OR json_extract(services.data, '\$.status') = 'pending'";
      expect(parseFilter(filter), expected);
    });

    test('parses logical OR with keyword (case-insensitive)', () {
      final filter = 'name = "test" or status = "pending"';
      final expected =
          "json_extract(services.data, '\$.name') = 'test' OR json_extract(services.data, '\$.status') = 'pending'";
      expect(parseFilter(filter), expected);
    });

    test('parses nested expressions with parentheses', () {
      final filter = 'id = "123" && (status = "done" || name ~ "task")';
      final expected =
          "id = '123' AND (json_extract(services.data, '\$.status') = 'done' OR json_extract(services.data, '\$.name') LIKE '%task%' ESCAPE '\\')";
      expect(parseFilter(filter), expected);
    });

    test('parses deeply nested expressions', () {
      final filter =
          '(name = "A" && (status = "B" || status = "C")) || id = "D"';
      final expected =
          "(json_extract(services.data, '\$.name') = 'A' AND (json_extract(services.data, '\$.status') = 'B' OR json_extract(services.data, '\$.status') = 'C')) OR id = 'D'";
      expect(parseFilter(filter), expected);
    });
  });

  group('Null Handling', () {
    test('parses null equality as IS NULL', () {
      final filter = 'completed_at = null';
      final expected = "json_extract(services.data, '\$.completed_at') IS NULL";
      expect(parseFilter(filter), expected);
    });

    test('parses null inequality as IS NOT NULL', () {
      final filter = 'user != null';
      final expected = "json_extract(services.data, '\$.user') IS NOT NULL";
      expect(parseFilter(filter), expected);
    });

    test('handles null with base fields', () {
      final filter = 'id = null';
      expect(parseFilter(filter), 'id IS NULL');
    });
  });

  group('Boolean Handling', () {
    test('parses true literal for JSON fields', () {
      final filter = 'active = true';
      // JSON fields use true/false literals
      final expected = "json_extract(services.data, '\$.active') = true";
      expect(parseFilter(filter), expected);
    });

    test('parses false literal for JSON fields', () {
      final filter = 'active = false';
      final expected = "json_extract(services.data, '\$.active') = false";
      expect(parseFilter(filter), expected);
    });

    test('parses boolean literals case-insensitively', () {
      expect(
        parseFilter('active = TRUE'),
        "json_extract(services.data, '\$.active') = true",
      );
      expect(
        parseFilter('active = False'),
        "json_extract(services.data, '\$.active') = false",
      );
    });
  });

  group('Numeric Handling', () {
    test('parses integer values', () {
      final filter = 'score > 100';
      final expected = "json_extract(services.data, '\$.score') > 100";
      expect(parseFilter(filter), expected);
    });

    test('parses decimal values', () {
      final filter = 'price = 19.99';
      final expected = "json_extract(services.data, '\$.price') = 19.99";
      expect(parseFilter(filter), expected);
    });

    test('parses negative numbers', () {
      final filter = 'temperature < -10';
      final expected = "json_extract(services.data, '\$.temperature') < -10";
      expect(parseFilter(filter), expected);
    });
  });

  group('Any-of Operators', () {
    test('parses ?= operator', () {
      final filter = 'tags ?= "flutter"';
      final expected =
          "EXISTS (SELECT 1 FROM json_each(json_extract(services.data, '\$.tags')) WHERE value = 'flutter')";
      expect(parseFilter(filter), expected);
    });

    test('parses ?!= operator', () {
      final filter = 'tags ?!= "deprecated"';
      final expected =
          "EXISTS (SELECT 1 FROM json_each(json_extract(services.data, '\$.tags')) WHERE value != 'deprecated')";
      expect(parseFilter(filter), expected);
    });

    test('parses ?~ operator with LIKE', () {
      final filter = 'tags ?~ "flutter"';
      final expected =
          "EXISTS (SELECT 1 FROM json_each(json_extract(services.data, '\$.tags')) WHERE value LIKE '%flutter%' ESCAPE '\\')";
      expect(parseFilter(filter), expected);
    });

    test('parses ?!~ operator', () {
      final filter = 'tags ?!~ "test"';
      final expected =
          "EXISTS (SELECT 1 FROM json_each(json_extract(services.data, '\$.tags')) WHERE value NOT LIKE '%test%' ESCAPE '\\')";
      expect(parseFilter(filter), expected);
    });

    test('parses ?> operator', () {
      final filter = 'scores ?> 80';
      final expected =
          "EXISTS (SELECT 1 FROM json_each(json_extract(services.data, '\$.scores')) WHERE value > 80)";
      expect(parseFilter(filter), expected);
    });

    test('parses ?>= operator', () {
      final filter = 'scores ?>= 80';
      final expected =
          "EXISTS (SELECT 1 FROM json_each(json_extract(services.data, '\$.scores')) WHERE value >= 80)";
      expect(parseFilter(filter), expected);
    });

    test('parses ?< operator', () {
      final filter = 'scores ?< 50';
      final expected =
          "EXISTS (SELECT 1 FROM json_each(json_extract(services.data, '\$.scores')) WHERE value < 50)";
      expect(parseFilter(filter), expected);
    });

    test('parses ?<= operator', () {
      final filter = 'scores ?<= 50';
      final expected =
          "EXISTS (SELECT 1 FROM json_each(json_extract(services.data, '\$.scores')) WHERE value <= 50)";
      expect(parseFilter(filter), expected);
    });
  });

  group('Field Modifiers', () {
    test('parses :lower modifier', () {
      final filter = 'name:lower = "john"';
      final expected = "LOWER(json_extract(services.data, '\$.name')) = 'john'";
      expect(parseFilter(filter), expected);
    });

    test('parses :lower modifier with LIKE', () {
      final filter = 'email:lower ~ "gmail"';
      final expected =
          "LOWER(json_extract(services.data, '\$.email')) LIKE '%gmail%' ESCAPE '\\'";
      expect(parseFilter(filter), expected);
    });

    test('parses :length modifier', () {
      final filter = 'tags:length > 2';
      final expected =
          "json_array_length(json_extract(services.data, '\$.tags')) > 2";
      expect(parseFilter(filter), expected);
    });

    test('parses :length modifier with equality', () {
      final filter = 'items:length = 0';
      final expected =
          "json_array_length(json_extract(services.data, '\$.items')) = 0";
      expect(parseFilter(filter), expected);
    });
  });

  group('DateTime Macros', () {
    // A Sunday in a leap-year February.
    final now = DateTime.utc(2024, 2, 11, 10, 30, 45, 123, 456);

    String macro(String name) => parseFilter('x = $name', now: now)
        .replaceFirst("json_extract(services.data, '\$.x') = ", '');

    test('formats datetime macros like PocketBase dates', () {
      expect(macro('@now'), "'2024-02-11 10:30:45.123Z'");
      expect(macro('@todayStart'), "'2024-02-11 00:00:00.000Z'");
      expect(macro('@todayEnd'), "'2024-02-11 23:59:59.999Z'");
      expect(macro('@yesterday'), "'2024-02-10 10:30:45.123Z'");
      expect(macro('@tomorrow'), "'2024-02-12 10:30:45.123Z'");
      expect(macro('@monthStart'), "'2024-02-01 00:00:00.000Z'");
      expect(macro('@monthEnd'), "'2024-02-29 23:59:59.999Z'");
      expect(macro('@yearStart'), "'2024-01-01 00:00:00.000Z'");
      expect(macro('@yearEnd'), "'2024-12-31 23:59:59.999Z'");
    });

    test('resolves numeric macros in UTC with Sunday as weekday 0', () {
      expect(macro('@second'), '45');
      expect(macro('@minute'), '30');
      expect(macro('@hour'), '10');
      expect(macro('@day'), '11');
      expect(macro('@weekday'), '0');
      expect(macro('@month'), '2');
      expect(macro('@year'), '2024');
      expect(
        parseFilter('x = @weekday', now: DateTime.utc(2024, 2, 17)),
        endsWith(' = 6'), // Saturday
      );
      // Local times are converted to UTC first.
      final local = DateTime.utc(2024, 2, 11, 23, 30).toLocal();
      expect(parseFilter('x = @hour', now: local), endsWith(' = 23'));
    });

    test('rolls @yesterday and @tomorrow across month boundaries', () {
      final firstOfMarch = DateTime.utc(2024, 3, 1, 8);
      expect(
        parseFilter('created > @yesterday', now: firstOfMarch),
        "created > '2024-02-29 08:00:00.000Z'",
      );
      expect(
        parseFilter('created < @tomorrow', now: DateTime.utc(2024, 12, 31)),
        "created < '2025-01-01 00:00:00.000Z'",
      );
    });

    test('does not treat macro names inside quoted text as macros', () {
      expect(
        parseFilter('note = "@now"'),
        "json_extract(services.data, '\$.note') = '@now'",
      );
    });
  });

  group('Comment Stripping', () {
    test('strips single-line comments', () {
      final filter = 'name = "test" // this is a comment';
      final expected = "json_extract(services.data, '\$.name') = 'test'";
      expect(parseFilter(filter), expected);
    });

    test('preserves // inside strings', () {
      final filter = 'url = "https://example.com"';
      final expected =
          "json_extract(services.data, '\$.url') = 'https://example.com'";
      expect(parseFilter(filter), expected);
    });
  });

  group('Quoted Literals', () {
    test('converts double quotes to single quotes', () {
      expect(parseFilter('name = "test"'),
          "json_extract(services.data, '\$.name') = 'test'");
    });

    test('doubles single quotes inside the SQL literal', () {
      expect(parseFilter("name = \"O'Brien\""), contains("= 'O''Brien'"));
      expect(parseFilter(r"name = 'O\'Brien'"), contains("= 'O''Brien'"));
    });

    test('unescapes backslash sequences like PocketBase', () {
      expect(parseFilter(r'name = "say \"hi\""'), contains("= 'say \"hi\"'"));
      expect(parseFilter(r'name = "a\\b"'), contains(r"= 'a\b'"));
      expect(parseFilter(r'name = "a\nb\tc\rd"'), contains("= 'a\nb\tc\rd'"));
      // Unknown escapes keep their backslash.
      expect(parseFilter(r'name = "\d\u00e9"'), contains(r"= '\d\u00e9'"));
    });

    test('keeps logical operators and parentheses inside quotes literal', () {
      expect(
        parseFilter(r'name = "a && (b) || \"c\" // d"'),
        "json_extract(services.data, '\$.name') = 'a && (b) || \"c\" // d'",
      );
    });

    test('keeps injection attempts inside the literal', () {
      expect(
        parseFilter("name = \"x' OR 1=1 --\""),
        "json_extract(services.data, '\$.name') = 'x'' OR 1=1 --'",
      );
      expect(
        parseFilter(r"name = 'x\' OR 1=1 --'"),
        "json_extract(services.data, '\$.name') = 'x'' OR 1=1 --'",
      );
    });

    test('escapes LIKE wildcards of contains matches like PocketBase', () {
      expect(
        parseFilter(r'name ~ "a_b\\c"'),
        "json_extract(services.data, '\$.name') LIKE '%a\\_b\\\\c%' ESCAPE '\\'",
      );
      expect(
        parseFilter("name ~ \"it's\""),
        "json_extract(services.data, '\$.name') LIKE '%it''s%' ESCAPE '\\'",
      );
    });
  });

  group('Base Fields', () {
    test('does not wrap base fields in json_extract', () {
      final filter = 'id = "123"';
      expect(parseFilter(filter), "id = '123'");
    });

    test('wraps non-base fields in json_extract', () {
      final filter = 'custom_field = "value"';
      expect(
        parseFilter(filter),
        "json_extract(services.data, '\$.custom_field') = 'value'",
      );
    });

    test('handles created and updated as base fields', () {
      expect(
        parseFilter('created > "2024-01-01"'),
        "created > '2024-01-01'",
      );
      expect(
        parseFilter('updated < "2024-12-31"'),
        "updated < '2024-12-31'",
      );
    });
  });

  group('Complex Filters', () {
    test('parses complex filter with mixed operators and nesting', () {
      final filter =
          'created > "2024-01-01" && (status = "active" || (priority > 5 && owner != null))';
      final expected =
          "created > '2024-01-01' AND (json_extract(services.data, '\$.status') = 'active' OR (json_extract(services.data, '\$.priority') > 5 AND json_extract(services.data, '\$.owner') IS NOT NULL))";
      expect(parseFilter(filter), expected);
    });

    test('handles whitespace variations', () {
      final filter = ' name   =   "test"   ||   status != "done" ';
      final expected =
          "json_extract(services.data, '\$.name') = 'test' OR json_extract(services.data, '\$.status') != 'done'";
      expect(parseFilter(filter), expected);
    });

    test('combines any-of with regular operators', () {
      final filter = 'tags ?= "flutter" && active = true';
      final result = parseFilter(filter);
      expect(result, contains('EXISTS'));
      expect(result, contains('AND'));
      expect(result, contains('= true'));
    });
  });

  group('Error Handling', () {
    test('throws FormatException for invalid filter', () {
      expect(
        () => parseFilter('invalid filter without operator'),
        throwsFormatException,
      );
    });

    test('throws FormatException for malformed filters', () {
      for (final filter in [
        'name = "unterminated',
        "name = 'it\\'",
        '(name = "a"',
        'name = "a")',
        'name = "a" &&',
        'name = "a" "b"',
        'name =',
        '()',
        '// only a comment',
        '"value" = name',
      ]) {
        expect(() => parseFilter(filter), throwsFormatException,
            reason: filter);
      }
    });

    test('resolves @request.auth.id to the logged-in account id', () {
      String parseAs(String filter, String? authId) => FilterParser(filter,
              baseFields: {'id', 'created', 'updated'}, authId: authId)
          .parse();

      expect(parseAs('author = @request.auth.id', 'u1'),
          parseAs('author = "u1"', null));
      expect(parseAs('author = @request.auth.id', null),
          parseAs('author = ""', null),
          reason: 'Like the server: empty when nobody is logged in');
    });

    test('rejects other request and collection macros with the offending token',
        () {
      for (final token in [
        '@request.auth.email',
        '@collection.posts.author',
        '@unknownMacro',
      ]) {
        expect(
          () => parseFilter('author = $token'),
          throwsA(isA<UnsupportedError>()
              .having((e) => e.message, 'message', contains('"$token"'))),
        );
      }
      expect(
        () => parseFilter('@request.auth.id != ""'),
        throwsA(isA<UnsupportedError>().having(
            (e) => e.message, 'message', contains('"@request.auth.id"'))),
      );
    });

    test('rejects unquoted field references', () {
      expect(
        () => parseFilter('status = active'),
        throwsA(isA<UnsupportedError>()
            .having((e) => e.message, 'message', contains('"active"'))),
      );
    });
  });
}
