import 'system_failure.dart';

/// A failure raised in the database layer.
///
/// Extends [SystemFailure]. The PostgreSQL implementation converts driver
/// exceptions into [DatabaseFailure]; the infra layer catches it and turns it
/// into a typed module failure.
class DatabaseFailure extends SystemFailure {
  DatabaseFailure({
    required super.errorMessage,
    required super.stackTrace,
    super.label = 'Database Failure',
    super.exception,
  });
}
