import 'package:flutter/foundation.dart';

/// Represents a single term in a filter expression, like `name = "value"`.
@immutable
class FilterTerm {
  const FilterTerm(this.field, this.operator, this.value);

  final String field;
  final String operator;
  final String? value; // Value can be null for operators like IS NULL

  @override
  String toString() => '$field $operator ${value ?? ''}'.trim();
}

/// Represents a logical operator in a filter expression.
enum LogicalOperator {
  and,
  or;

  @override
  String toString() => name.toUpperCase();
}

/// A class responsible for parsing a PocketBase filter string into a valid
/// SQL `WHERE` clause for Drift.
class FilterParser {
  FilterParser(this.filter, {required this.baseFields});

  final String filter;
  final Set<String> baseFields;
  final List<dynamic> _tokens = [];

  /// Parses the filter string and generates the SQL WHERE clause.
  String parse() {
    _tokenize();
    return _buildSql();
  }

  /// Breaks the filter string into a series of [FilterTerm]s, [LogicalOperator]s,
  /// and nested [FilterParser] instances for parenthesized groups. This tokenizer
  /// correctly handles operators inside quoted strings and nested parentheses.
  void _tokenize() {
    // Use word boundaries (\b) to ensure 'AND' and 'OR' are matched as whole words
    // and not as parts of other words (e.g., the 'or' in 'priority').
    final logicalRegex =
        RegExp(r'\s*(&&|\|\||\bAND\b|\bOR\b)\s*', caseSensitive: false);

    // This regex is now more complex. It has two main parts connected by a `|` (OR):
    // 1. The original part for `field operator value`
    // 2. A new part for `field IS (NOT) NULL`
    final termRegex = RegExp(
        r'^\s*([\w\.\-]+)\s*((?:NOT LIKE)|(?:!~)|(?:!=)|(?:>=)|(?:<=)|(?:LIKE)|~|=|>|<|(?:IS NOT NULL)|(?:IS NULL))\s*(.*)\s*$',
        caseSensitive: false);

    int balance = 0;
    int lastSplit = 0;
    bool inSingleQuote = false;
    bool inDoubleQuote = false;

    for (int i = 0; i < filter.length; i++) {
      final char = filter[i];

      // Toggle quote state if the quote is not escaped.
      final isEscaped = i > 0 && filter[i - 1] == r'\';
      if (!isEscaped) {
        if (char == "'" && !inDoubleQuote) {
          inSingleQuote = !inSingleQuote;
        } else if (char == '"' && !inSingleQuote) {
          inDoubleQuote = !inDoubleQuote;
        }
      }

      // If we are inside a quote, we don't care about operators or parentheses.
      if (inSingleQuote || inDoubleQuote) {
        continue;
      }

      if (char == '(') {
        balance++;
      } else if (char == ')') {
        balance--;
      } else if (balance == 0) {
        // Potential logical operator found at the top level (not in parentheses or quotes).
        final match = logicalRegex.matchAsPrefix(filter, i);
        if (match != null) {
          final termString = filter.substring(lastSplit, i).trim();
          if (termString.isNotEmpty) {
            _addTerm(termString, termRegex);
          }

          final operator = match.group(1)!.toUpperCase();
          if (operator == '&&' || operator == 'AND') {
            _tokens.add(LogicalOperator.and);
          } else if (operator == '||' || operator == 'OR') {
            _tokens.add(LogicalOperator.or);
          }

          i = match.end - 1; // Move cursor past the operator
          lastSplit = match.end;
        }
      }
    }

    // Add the final term after the last operator.
    final lastTermString = filter.substring(lastSplit).trim();
    if (lastTermString.isNotEmpty) {
      _addTerm(lastTermString, termRegex);
    }
  }

  /// Adds a parsed term or a nested parser to the token list.
  void _addTerm(String termString, RegExp termRegex) {
    // Handle parenthesis by recursively parsing the inner content.
    if (termString.startsWith('(') && termString.endsWith(')')) {
      final innerFilter = termString.substring(1, termString.length - 1);
      final subParser = FilterParser(innerFilter, baseFields: baseFields);
      _tokens.add(subParser); // Add the sub-parser itself as a token.
    } else {
      final termMatch = termRegex.firstMatch(termString);
      if (termMatch != null) {
        final field = termMatch.group(1)!.trim();
        final operator = termMatch.group(2)!.trim();
        final value = termMatch.group(3)!.trim();

        // For IS NULL and IS NOT NULL, the value part from regex will be empty.
        _tokens.add(FilterTerm(field, operator, value.isEmpty ? null : value));
      } else {
        throw FormatException('Invalid filter term: "$termString"');
      }
    }
  }

  /// A helper function to correctly quote a field for SQL based on whether it's
  /// a base field or a JSON field.
  String _quoteField(String field) {
    if (baseFields.contains(field.toLowerCase())) {
      return field;
    }
    // All other fields are assumed to be in the 'data' JSON column.
    // This also correctly handles special keys like `synced` or `isNew`.
    return "json_extract(services.data, '\$.$field')";
  }

  /// Translates a PocketBase operator to its SQLite equivalent.
  String _translateOperator(String pbOperator) {
    switch (pbOperator.toUpperCase()) {
      // Use toUpperCase to handle 'like' and 'LIKE'
      case '~':
        return 'LIKE';
      case '!~':
        return 'NOT LIKE';
      default:
        return pbOperator;
    }
  }

  /// Builds the final SQL string from the tokenized parts.
  String _buildSql() {
    final sqlParts = <String>[];
    for (final token in _tokens) {
      if (token is FilterTerm) {
        final fieldSql = _quoteField(token.field);
        final operatorSql = _translateOperator(token.operator);

        // Handle operators with and without values
        if (token.value == null) {
          sqlParts.add('$fieldSql $operatorSql');
        } else {
          String valueSql = token.value!;
          // PocketBase's LIKE operators (~ and !~) auto-wrap the value in '%'
          // if no wildcard is present. We replicate that behavior here.
          if (token.operator == '~' || token.operator == '!~') {
            // The value comes from the regex with its quotes intact (e.g., '"test"').
            // We need to check if the content inside the quotes has a '%'.
            if (!valueSql.substring(1, valueSql.length - 1).contains('%')) {
              final unquotedValue = valueSql.substring(1, valueSql.length - 1);
              // Re-quote with the wildcards.
              valueSql = "'%${unquotedValue.replaceAll("'", "''")}%'";
            }
          }
          sqlParts.add('$fieldSql $operatorSql $valueSql');
        }
      } else if (token is LogicalOperator) {
        sqlParts.add(token.toString());
      } else if (token is FilterParser) {
        // Recursively build the SQL for the sub-query and wrap it in parentheses.
        sqlParts.add('(${token.parse()})');
      }
    }
    return sqlParts.join(' ');
  }
}
