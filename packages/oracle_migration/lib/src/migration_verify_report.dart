import 'applied_migration.dart';
import 'migration.dart';

/// An applied migration whose checksum no longer matches the filesystem — or
/// that is missing from the filesystem entirely ([filesystem] is null).
class ChecksumMismatch {
  /// The migration as recorded in `_migrations`.
  final AppliedMigration applied;

  /// The migration as it currently exists on disk, or null if it was removed.
  final Migration? filesystem;

  const ChecksumMismatch({required this.applied, required this.filesystem});
}

/// Integrity report comparing `_migrations` against the filesystem.
class MigrationVerifyReport {
  /// Applied migrations that drifted (changed or removed on disk).
  final List<ChecksumMismatch> mismatches;

  /// Filesystem migrations not yet applied.
  final List<Migration> pending;

  /// Applied migrations that still match their files.
  final List<AppliedMigration> verified;

  const MigrationVerifyReport({
    required this.mismatches,
    required this.pending,
    required this.verified,
  });

  /// True when there are no checksum mismatches.
  bool get isValid => mismatches.isEmpty;
}
