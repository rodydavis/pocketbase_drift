/// A class responsible for parsing a PocketBase filter string into a valid
/// SQL `WHERE` clause for Drift.
///
/// This parser accepts **PocketBase-compatible filter syntax** and translates
/// it to SQLite-compatible SQL. This ensures filters can work on both the
/// remote PocketBase server and the local SQLite cache.
///
/// ## Supported Features
///
/// **Operators:**
/// - `=`, `!=`, `>`, `>=`, `<`, `<=`
/// - `~` (LIKE/Contains), `!~` (NOT LIKE)
/// - `?=`, `?!=`, `?>`, `?>=`, `?<`, `?<=`, `?~`, `?!~` (any-of operators for arrays)
///
/// **Logical operators:**
/// - `&&` or `AND`
/// - `||` or `OR`
/// - `(...)` for grouping
///
/// **Value types:**
/// - Strings: `"value"` or `'value'`, with the same backslash escapes as
///   PocketBase (`\"`, `\'`, `\\`, `\n`, `\t`, `\r`; any other escaped
///   character keeps its backslash). Values produced by the SDK's
///   `pb.filter('title = {:t}', {'t': value})` therefore match the same
///   records locally as on the server.
/// - Numbers: `123`, `19.99`, `-10`
/// - Booleans: `true`, `false`
/// - Null: `null`
///
/// **DateTime macros** (UTC, formatted like PocketBase dates,
/// e.g. `2026-11-04 00:00:00.000Z`):
/// - `@now`, `@todayStart`, `@todayEnd`
/// - `@yesterday`, `@tomorrow` (the current time one day earlier/later)
/// - `@monthStart`, `@monthEnd`, `@yearStart`, `@yearEnd`
/// - `@second`, `@minute`, `@hour`, `@day`, `@weekday` (0 = Sunday),
///   `@month`, `@year`
///
/// **Field modifiers:**
/// - `:lower` - Case-insensitive comparison
/// - `:length` - Array length check
///
/// **Comments:**
/// - `// single line comments` are stripped
///
/// ## Errors
///
/// - Malformed filters (unterminated quotes, unbalanced parentheses, missing
///   operators or values) throw a [FormatException].
/// - Right-hand operands that are neither literals, datetime macros nor
///   `@request.auth.id`, such as other `@request.*` values, `@collection.*`
///   or field references, throw an [UnsupportedError]: the local cache
///   cannot evaluate them.
///
/// `@request.auth.id` is the id of the logged-in account ([authId]), or an
/// empty string when nobody is logged in, as on the server.
///
/// Every value is emitted as a SQL literal; quoted text can never escape its
/// literal and inject SQL.
class FilterParser {
  FilterParser(this.filter, {required this.baseFields, this.now, this.authId});

  final String filter;
  final Set<String> baseFields;

  /// Reference time for the datetime macros. Defaults to the current time.
  final DateTime? now;

  /// Value of `@request.auth.id`.
  final String? authId;

  /// Parses the filter string and generates the SQL WHERE clause.
  String parse() {
    final reader = _FilterReader(
      filter,
      baseFields: baseFields,
      macros: {
        ..._datetimeMacros((now ?? DateTime.now()).toUtc()),
        '@request.auth.id': _Operand(_ValueType.string, authId ?? ''),
      },
    );
    return reader.read();
  }

  /// Resolves the PocketBase datetime macros for [now] (in UTC), mirroring
  /// `tools/search/identifier_macros.go`.
  static Map<String, _Operand> _datetimeMacros(DateTime now) {
    _Operand date(DateTime value) =>
        _Operand(_ValueType.string, _formatPocketBaseDate(value));
    _Operand number(int value) => _Operand(_ValueType.number, '$value');

    return {
      '@now': date(now),
      '@yesterday': date(
        DateTime.utc(
          now.year,
          now.month,
          now.day - 1,
          now.hour,
          now.minute,
          now.second,
          now.millisecond,
          now.microsecond,
        ),
      ),
      '@tomorrow': date(
        DateTime.utc(
          now.year,
          now.month,
          now.day + 1,
          now.hour,
          now.minute,
          now.second,
          now.millisecond,
          now.microsecond,
        ),
      ),
      '@todayStart': date(DateTime.utc(now.year, now.month, now.day)),
      '@todayEnd': date(
        DateTime.utc(now.year, now.month, now.day, 23, 59, 59, 999),
      ),
      '@monthStart': date(DateTime.utc(now.year, now.month)),
      '@monthEnd': date(
        DateTime.utc(now.year, now.month + 1, 0, 23, 59, 59, 999),
      ),
      '@yearStart': date(DateTime.utc(now.year)),
      '@yearEnd': date(DateTime.utc(now.year, 12, 31, 23, 59, 59, 999)),
      '@second': number(now.second),
      '@minute': number(now.minute),
      '@hour': number(now.hour),
      '@day': number(now.day),
      '@weekday': number(now.weekday % DateTime.daysPerWeek),
      '@month': number(now.month),
      '@year': number(now.year),
    };
  }

  /// Formats [value] (UTC) like PocketBase's `types.DateTime`
  /// (`2006-01-02 15:04:05.000Z`).
  static String _formatPocketBaseDate(DateTime value) {
    String pad(int n, [int width = 2]) => n.toString().padLeft(width, '0');
    return '${pad(value.year, 4)}-${pad(value.month)}-${pad(value.day)} '
        '${pad(value.hour)}:${pad(value.minute)}:${pad(value.second)}.'
        '${pad(value.millisecond, 3)}Z';
  }
}

enum _ValueType { string, number, boolean, nullValue }

/// A resolved right-hand operand. [value] holds the unescaped text of strings
/// and the literal text of numbers.
class _Operand {
  const _Operand(this.type, [this.value]);

  final _ValueType type;
  final String? value;
}

/// Single-pass reader that translates a filter string into SQL.
class _FilterReader {
  _FilterReader(this.input, {required this.baseFields, required this.macros});

  final String input;
  final Set<String> baseFields;
  final Map<String, _Operand> macros;
  int _pos = 0;

  /// Operators ordered so that longer operators are matched first.
  static const _operators = [
    '?!~', '?!=', '?>=', '?<=', '?>', '?<', '?~', '?=', //
    '!~', '!=', '>=', '<=', '~', '=', '>', '<',
  ];
  static const _likeOperators = {'~', '!~', '?~', '?!~'};
  static final _identifierChar = RegExp(r'[\w.\-@#:]');
  static final _fieldPattern = RegExp(r'^([\w.\-]+)(?::(\w+))?$');
  static final _numberPattern = RegExp(r'^-?\d+\.?\d*$');

  bool get _atEnd => _pos >= input.length;

  String read() {
    final sql = _readExpression(nested: false);
    if (sql.isEmpty) {
      throw FormatException('Empty filter expression', input);
    }
    return sql;
  }

  /// Reads terms and groups joined by logical operators until the end of the
  /// input or, when [nested], until the closing parenthesis.
  String _readExpression({required bool nested}) {
    final parts = <String>[];
    while (true) {
      _skipWhitespaceAndComments();
      if (_atEnd || input[_pos] == ')') {
        if (parts.isNotEmpty) {
          throw FormatException(
            'Expected an expression after the logical operator',
            input,
            _pos,
          );
        }
        break;
      }

      parts.add(_readOperand());

      _skipWhitespaceAndComments();
      if (_atEnd || input[_pos] == ')') break;

      final join = _readJoin();
      if (join == null) {
        throw FormatException(
          'Expected "&&" or "||" between filter expressions',
          input,
          _pos,
        );
      }
      parts.add(join);
    }

    if (nested) {
      if (_atEnd) {
        throw FormatException('Missing closing parenthesis', input, _pos);
      }
      _pos++; // consume ')'
    } else if (!_atEnd) {
      throw FormatException('Unexpected closing parenthesis', input, _pos);
    }

    return parts.join(' ');
  }

  String _readOperand() {
    if (input[_pos] != '(') return _readTerm();

    final start = _pos;
    _pos++; // consume '('
    final inner = _readExpression(nested: true);
    if (inner.isEmpty) {
      throw FormatException('Empty parenthesized expression', input, start);
    }
    return '($inner)';
  }

  /// Reads `&&`, `||` or the `AND` / `OR` keywords (case-insensitive).
  String? _readJoin() {
    if (input.startsWith('&&', _pos)) {
      _pos += 2;
      return 'AND';
    }
    if (input.startsWith('||', _pos)) {
      _pos += 2;
      return 'OR';
    }
    final start = _pos;
    final word = _readIdentifier().toUpperCase();
    if (word == 'AND' || word == 'OR') return word;
    _pos = start;
    return null;
  }

  /// Reads a single `field operator value` comparison.
  String _readTerm() {
    final start = _pos;
    final left = _readIdentifier();
    if (left.startsWith('@')) {
      throw UnsupportedError(
        'The filter token "$left" cannot be evaluated against the local '
        'cache.',
      );
    }
    final fieldMatch = _fieldPattern.firstMatch(left);
    if (fieldMatch == null) {
      throw FormatException(
        'Invalid filter term: expected a field name',
        input,
        start,
      );
    }
    final field = fieldMatch.group(1)!;
    final modifier = fieldMatch.group(2)?.toLowerCase();

    _skipWhitespaceAndComments();
    final operator = _operators.firstWhere(
      (op) => input.startsWith(op, _pos),
      orElse: () => throw FormatException(
        'Invalid filter term: expected an operator after "$left"',
        input,
        _pos,
      ),
    );
    _pos += operator.length;

    _skipWhitespaceAndComments();
    final operand = _readValue(left, operator);
    return _buildTerm(field, modifier, operator, operand);
  }

  _Operand _readValue(String left, String operator) {
    if (_atEnd) {
      throw FormatException(
        'Invalid filter term: missing value after "$left $operator"',
        input,
        _pos,
      );
    }

    final char = input[_pos];
    if (char == '"' || char == "'") {
      return _Operand(_ValueType.string, _readQuotedText());
    }

    final start = _pos;
    final token = _readIdentifier();
    if (token.isEmpty) {
      throw FormatException(
        'Invalid filter term: missing value after "$left $operator"',
        input,
        start,
      );
    }

    final lower = token.toLowerCase();
    if (lower == 'null') return const _Operand(_ValueType.nullValue);
    if (lower == 'true') return const _Operand(_ValueType.boolean, '1');
    if (lower == 'false') return const _Operand(_ValueType.boolean, '0');
    if (_numberPattern.hasMatch(token)) {
      return _Operand(_ValueType.number, token);
    }

    final macro = macros[token];
    if (macro != null) return macro;

    if (token.startsWith('@')) {
      throw UnsupportedError(
        'The filter token "$token" cannot be evaluated against the local '
        'cache; only literals and the datetime macros are supported.',
      );
    }
    throw UnsupportedError(
      'The unquoted filter value "$token" cannot be evaluated against the '
      'local cache; field references are not supported. Quote text values '
      '(e.g. "$token").',
    );
  }

  /// Reads a quoted text literal starting at the current position and returns
  /// its unescaped content, mirroring the PocketBase (fexpr) scanner.
  String _readQuotedText() {
    final start = _pos;
    final quote = input[_pos++];
    final buffer = StringBuffer();
    var escapeNext = false;

    // fexpr treats U+0000 as the end of the input.
    while (!_atEnd && input.codeUnitAt(_pos) != 0) {
      final char = input[_pos++];
      if (escapeNext) {
        escapeNext = false;
        switch (char) {
          case 'n':
            buffer.write('\n');
          case 't':
            buffer.write('\t');
          case 'r':
            buffer.write('\r');
          case r'\':
          case "'":
          case '"':
            buffer.write(char);
          default:
            buffer
              ..write(r'\')
              ..write(char);
        }
      } else if (char == r'\') {
        escapeNext = true;
      } else if (char == quote) {
        return buffer.toString();
      } else {
        buffer.write(char);
      }
    }

    throw FormatException('Unterminated quoted text', input, start);
  }

  /// Reads a run of identifier characters (field names, keywords, numbers
  /// and macros).
  String _readIdentifier() {
    final start = _pos;
    while (!_atEnd && _identifierChar.hasMatch(input[_pos])) {
      _pos++;
    }
    return input.substring(start, _pos);
  }

  void _skipWhitespaceAndComments() {
    while (!_atEnd) {
      final char = input[_pos];
      if (char == ' ' || char == '\t' || char == '\n' || char == '\r') {
        _pos++;
      } else if (input.startsWith('//', _pos)) {
        final end = input.indexOf('\n', _pos);
        _pos = end == -1 ? input.length : end + 1;
      } else {
        break;
      }
    }
  }

  String _buildTerm(
    String field,
    String? modifier,
    String operator,
    _Operand operand,
  ) {
    final isAnyOf = operator.startsWith('?');
    final baseOperator = isAnyOf ? operator.substring(1) : operator;
    final isBaseField = baseFields.contains(field.toLowerCase());

    if (operand.type == _ValueType.nullValue) {
      final fieldSql = _fieldSql(field, modifier);
      return baseOperator == '!='
          ? '$fieldSql IS NOT NULL'
          : '$fieldSql IS NULL';
    }

    final String valueSql;
    String sqlOperator = baseOperator;
    String suffix = '';
    if (_likeOperators.contains(operator)) {
      // Like PocketBase, non-text operands are matched by their text form.
      sqlOperator = baseOperator == '~' ? 'LIKE' : 'NOT LIKE';
      valueSql = _sqlString(_likePattern(operand.value!));
      suffix = r" ESCAPE '\'";
    } else {
      valueSql = switch (operand.type) {
        // SQLite reads the `true`/`false` keywords as 1/0, which is also how
        // json_extract returns JSON booleans.
        _ValueType.boolean when !isBaseField =>
          operand.value == '1' ? 'true' : 'false',
        _ValueType.string => _sqlString(operand.value!),
        _ValueType.boolean || _ValueType.number => operand.value!,
        _ValueType.nullValue => 'NULL',
      };
    }

    if (isAnyOf) {
      final jsonPath = isBaseField
          ? field
          : "json_extract(services.data, '\$.$field')";
      return 'EXISTS (SELECT 1 FROM json_each($jsonPath) '
          'WHERE value $sqlOperator $valueSql$suffix)';
    }
    return '${_fieldSql(field, modifier)} $sqlOperator $valueSql$suffix';
  }

  /// Returns the SQL expression for [field], which is either a real column
  /// (base fields) or a value in the `data` JSON column.
  String _fieldSql(String field, String? modifier) {
    final isBaseField = baseFields.contains(field.toLowerCase());
    final fieldSql = isBaseField
        ? field
        : "json_extract(services.data, '\$.$field')";

    switch (modifier) {
      case 'lower':
        return 'LOWER($fieldSql)';
      case 'length':
        return isBaseField
            ? 'LENGTH($fieldSql)'
            : "json_array_length(json_extract(services.data, '\$.$field'))";
      default:
        return fieldSql;
    }
  }

  /// Quotes [value] as a SQLite string literal.
  static String _sqlString(String value) => "'${value.replaceAll("'", "''")}'";

  /// Mirrors PocketBase's `wrapLikeParams`: values without an unescaped `%`
  /// get their `\`, `%` and `_` escaped and are wrapped in `%` for a contains
  /// match; values with an explicit `%` wildcard are used as-is.
  static String _likePattern(String value) {
    if (_containsUnescaped(value, '%')) return value;
    return '%${_escapeUnescaped(value, const {r'\', '%', '_'})}%';
  }

  static bool _containsUnescaped(String value, String char) {
    var previous = '';
    for (var i = 0; i < value.length; i++) {
      final c = value[i];
      if (c == char && previous != r'\') return true;
      // A double backslash is an escaped backslash, not an escape sequence.
      previous = c == r'\' && previous == r'\' ? '' : c;
    }
    return false;
  }

  static String _escapeUnescaped(String value, Set<String> chars) {
    final result = <String>[];
    var match = false;
    for (var i = value.length - 1; i >= 0; i--) {
      final c = value[i];
      if (match) {
        if (c != r'\') result.add(r'\');
        match = false;
      } else {
        match = chars.contains(c);
      }
      result.add(c);
      if (i == 0 && match) result.add(r'\');
    }
    return result.reversed.join();
  }
}
