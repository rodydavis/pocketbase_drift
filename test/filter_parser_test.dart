import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase_drift/pocketbase_drift.dart';

void main() {
  group('Advanced FilterParser Capabilities', () {
    // Helper function to easily test the parser
    String parseFilter(String filter) {
      final baseFields = {'id', 'created', 'updated'};
      final parser = FilterParser(filter, baseFields: baseFields);
      return parser.parse();
    }

    test('parses logical OR operator correctly', () {
      // Using '||'
      var filter = 'name = "test" || status = "pending"';
      var expectedSql =
          "json_extract(services.data, '\$.name') = \"test\" OR json_extract(services.data, '\$.status') = \"pending\"";
      expect(parseFilter(filter), expectedSql);

      // Using 'OR' (case-insensitive)
      filter = 'name = "test" or status = "pending"';
      expect(parseFilter(filter), expectedSql);
    });

    test('parses nested expressions with parentheses correctly', () {
      final filter = 'id = "123" && (status = "done" || name ~ "task")';
      final expectedSql =
          "id = \"123\" AND (json_extract(services.data, '\$.status') = \"done\" OR json_extract(services.data, '\$.name') LIKE '%task%')";
      expect(parseFilter(filter), expectedSql);
    });

    test('parses deeply nested expressions correctly', () {
      final filter =
          '(name = "A" && (status = "B" || status = "C")) || id = "D"';
      final expectedSql =
          "(json_extract(services.data, '\$.name') = \"A\" AND (json_extract(services.data, '\$.status') = \"B\" OR json_extract(services.data, '\$.status') = \"C\")) OR id = \"D\"";
      expect(parseFilter(filter), expectedSql);
    });

    test('parses IS NULL and IS NOT NULL operators', () {
      // IS NULL
      var filter = 'completed_at IS NULL';
      var expectedSql =
          "json_extract(services.data, '\$.completed_at') IS NULL";
      expect(parseFilter(filter), expectedSql);

      // IS NOT NULL (case-insensitive)
      filter = 'user is not null';
      expectedSql = "json_extract(services.data, '\$.user') is not null";
      expect(parseFilter(filter), expectedSql);
    });

    test('parses complex filter with mixed operators and nesting', () {
      final filter =
          'created > "2024-01-01" && (status = "active" || (priority > 5 && owner IS NOT NULL))';
      final expectedSql =
          "created > \"2024-01-01\" AND (json_extract(services.data, '\$.status') = \"active\" OR (json_extract(services.data, '\$.priority') > 5 AND json_extract(services.data, '\$.owner') IS NOT NULL))";
      expect(parseFilter(filter), expectedSql);
    });

    test('handles whitespace and different operator casings', () {
      final filter = ' name   =   "test"   OR   status != "done" ';
      final expectedSql =
          "json_extract(services.data, '\$.name') = \"test\" OR json_extract(services.data, '\$.status') != \"done\"";
      expect(parseFilter(filter), expectedSql);
    });
  });
}
