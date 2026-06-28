/// Base class for immutable, value-compared domain primitives.
///
/// Wraps a non-null [value]; use a nullable field (`SomeVO?`) for optional
/// values. Equality and hashing are by [value].
abstract class ValueObject<T extends Object> {
  final T value;

  const ValueObject(this.value);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other.runtimeType == runtimeType && other is ValueObject<T> && other.value == value);

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => '$runtimeType($value)';
}
