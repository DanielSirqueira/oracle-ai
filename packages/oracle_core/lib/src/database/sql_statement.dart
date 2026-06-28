import 'package:collection/collection.dart';

/// Matches named placeholders `:name` in SQL while ignoring string literals and
/// PostgreSQL casts.
///
/// Ordered alternatives (first match wins):
/// 1. **String literal** between single quotes (`'abc'`, `'a''b'`) — ignored.
/// 2. **PostgreSQL cast** `::type` (e.g. `col::varchar`, `:p::int`) — ignored,
///    so `::vector` is not mistaken for a `:vector` placeholder.
/// 3. **Named placeholder** `:identifier` — captured in group 1.
final _placeholderOrLiteralRegex = RegExp(
  r"'(?:[^']|'')*'" // string literal (handles '' escape)
  r"|::[a-zA-Z_][a-zA-Z0-9_]*" // PostgreSQL cast (no capture group)
  r"|:([a-zA-Z_][a-zA-Z0-9_]*)", // named placeholder (group 1)
);

/// Immutable, parameterized SQL statement.
///
/// **Security rule:** values from user input or any untrusted source MUST be
/// passed in [params] and referenced by named placeholders `:name` in [sql].
/// Never interpolate values directly into [sql] — that enables SQL injection.
///
/// ```dart
/// const s = SqlStatement(
///   'SELECT * FROM users WHERE email = :email',
///   {'email': userInput},
/// );
/// ```
class SqlStatement {
  /// SQL text — use named placeholders `:name` for dynamic values.
  final String sql;

  /// Named parameters. Keys are the names without the `:` prefix.
  final Map<String, Object?> params;

  const SqlStatement(this.sql, [this.params = const {}]);

  /// Validates that every placeholder in [sql] has a matching entry in [params].
  ///
  /// Placeholders inside string literals are ignored. Extra params (not
  /// referenced by the SQL) are tolerated — drivers only bind what appears in
  /// the SQL, which lets the same param map be reused across INSERT/UPDATE.
  ///
  /// Throws [FormatException] only when a placeholder has no matching param.
  void validate() {
    final placeholders = <String>{};
    for (final match in _placeholderOrLiteralRegex.allMatches(sql)) {
      final placeholder = match.group(1);
      if (placeholder != null) placeholders.add(placeholder);
    }

    final missing = placeholders.difference(params.keys.toSet());
    if (missing.isNotEmpty) {
      throw FormatException(
        'Invalid SqlStatement — placeholders without params: $missing. SQL: $sql',
      );
    }
  }

  /// Appends a fragment to the SQL and merges [extraParams].
  ///
  /// Throws [ArgumentError] if [extraParams] redefines an existing key with a
  /// different value (prevents silent overwrite).
  SqlStatement append(String fragment, [Map<String, Object?> extraParams = const {}]) {
    for (final key in extraParams.keys) {
      if (params.containsKey(key) && params[key] != extraParams[key]) {
        throw ArgumentError(
          'append: key "$key" already exists with a different value. '
          'Rename the placeholder to avoid the collision.',
        );
      }
    }
    return SqlStatement('$sql$fragment', {...params, ...extraParams});
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SqlStatement &&
        other.sql == sql &&
        const MapEquality<String, Object?>().equals(other.params, params);
  }

  @override
  int get hashCode => Object.hash(sql, const MapEquality<String, Object?>().hash(params));

  @override
  String toString() => 'SqlStatement(sql: $sql, params: $params)';
}
