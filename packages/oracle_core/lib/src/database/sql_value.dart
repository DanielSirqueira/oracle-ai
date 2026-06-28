/// Typed SQL values for use in [SqlStatement] parameters.
///
/// This sealed hierarchy lets the caller declare the exact SQL type of a
/// parameter instead of relying on driver inference. Each [Database]
/// implementation unwraps a [SqlValue] to its driver's native type.
///
/// For most cases passing the raw Dart value works (the driver infers the
/// type). Reach for a [SqlValue] when inference is wrong (e.g. a numeric
/// string that must be `bigint`, not `text`), for typed `NULL`s, or for
/// complex types such as `jsonb`, arrays or `vector`.
sealed class SqlValue<T extends Object> {
  /// Transported Dart value. `null` represents SQL `NULL`.
  final T? value;

  const SqlValue(this.value);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other.runtimeType == runtimeType && other is SqlValue<T> && other.value == value);

  @override
  int get hashCode => Object.hash(runtimeType, value);

  @override
  String toString() => '$runtimeType($value)';
}

/// Short/variable string. Maps to `varchar`/`text`.
class SqlVarchar extends SqlValue<String> {
  const SqlVarchar(super.value);
}

/// Long string. Maps to `text`.
class SqlText extends SqlValue<String> {
  const SqlText(super.value);
}

/// 32-bit integer. Maps to `integer`.
class SqlInt extends SqlValue<int> {
  const SqlInt(super.value);
}

/// Large integer. Maps to `bigint`.
class SqlBigInt extends SqlValue<BigInt> {
  const SqlBigInt(super.value);
}

/// 64-bit float. Maps to `double precision`.
class SqlDouble extends SqlValue<double> {
  const SqlDouble(super.value);
}

/// Boolean. Maps to `boolean`.
class SqlBool extends SqlValue<bool> {
  const SqlBool(super.value);
}

/// Date (no time). Maps to `date`.
class SqlDate extends SqlValue<DateTime> {
  const SqlDate(super.value);
}

/// Date with time. Maps to `timestamp`.
class SqlTimestamp extends SqlValue<DateTime> {
  const SqlTimestamp(super.value);
}

/// Binary JSON. Maps to `jsonb`.
class SqlJsonb extends SqlValue<Object> {
  const SqlJsonb(super.value);
}

/// Typed array. Maps to `T[]`.
class SqlArray<T extends Object> extends SqlValue<List<T>> {
  const SqlArray(super.value);
}

/// pgvector embedding. Maps to the pgvector text literal (`[0.1,0.2,...]`).
///
/// Because the `postgres` driver does not know the `vector` OID, send the
/// value with an explicit cast in the SQL, e.g. `:embedding::vector(1024)`.
class SqlVector extends SqlValue<List<double>> {
  const SqlVector(super.value);

  /// pgvector text literal for [value], e.g. `[0.1,0.2,0.3]`.
  static String literal(List<double> v) => '[${v.join(',')}]';
}
