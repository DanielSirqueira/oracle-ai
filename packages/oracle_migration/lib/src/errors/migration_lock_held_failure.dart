import 'migration_failure.dart';

/// Raised when another process already holds the migration lock.
class MigrationLockHeldFailure extends MigrationFailure {
  /// Owner currently holding the lock, if known.
  final String? lockedBy;

  /// When the lock was acquired, if known.
  final DateTime? lockedAt;

  MigrationLockHeldFailure({
    this.lockedBy,
    this.lockedAt,
    required super.stackTrace,
  }) : super(label: 'Migration Lock Held', errorMessage: _message(lockedBy, lockedAt));

  static String _message(String? by, DateTime? at) {
    final byPart = by != null ? ' by $by' : '';
    final atPart = at != null ? ' since $at' : '';
    return 'Migration lock is held$byPart$atPart.';
  }
}
