import 'package:postgres/postgres.dart';

import '../sql_value.dart';

/// Translates a value into the form expected by the `postgres` driver.
///
/// - A raw `Object?` passes through (the driver infers the type).
/// - A [SqlValue] is wrapped in a [TypedValue] with the right [Type], so the
///   driver sends the exact declared type.
///
/// Exposed at top level so it can be unit-tested without a real connection.
Object? unwrapSqlValueForPostgres(Object? value) {
  if (value is! SqlValue) return value;

  return switch (value) {
    // PostgreSQL has no exposed `varchar` Type; `text` covers variable-length
    // strings the same way.
    SqlVarchar() => TypedValue(Type.text, value.value),
    SqlText() => TypedValue(Type.text, value.value),
    SqlInt() => TypedValue(Type.integer, value.value),
    SqlBigInt() => TypedValue(Type.bigInteger, value.value),
    SqlDouble() => TypedValue(Type.double, value.value),
    SqlBool() => TypedValue(Type.boolean, value.value),
    SqlDate() => TypedValue(Type.date, value.value),
    SqlTimestamp() => TypedValue(Type.timestamp, value.value),
    SqlJsonb() => TypedValue(Type.jsonb, value.value),
    // Untyped array: the driver detects the element type. `unspecified` lets
    // the server infer from context (e.g. `ARRAY[:v]`).
    SqlArray() => TypedValue(Type.unspecified, value.value),
    // pgvector: sent as the text literal `[..]`; the SQL must cast it, e.g.
    // `:embedding::vector(1024)`.
    SqlVector() => TypedValue(
        Type.text,
        value.value == null ? null : SqlVector.literal(value.value as List<double>),
      ),
  };
}

/// Applies [unwrapSqlValueForPostgres] to every value in [params].
Map<String, Object?> unwrapParamsForPostgres(Map<String, Object?> params) {
  return params.map((k, v) => MapEntry(k, unwrapSqlValueForPostgres(v)));
}
