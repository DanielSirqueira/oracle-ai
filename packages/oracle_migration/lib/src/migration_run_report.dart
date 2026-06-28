import 'applied_migration.dart';
import 'migration.dart';

/// Outcome of a migration run (`up`).
class MigrationRunReport {
  /// Migrations applied successfully in this run.
  final List<AppliedMigration> applied;

  /// Migrations skipped because they were already applied.
  final List<Migration> skipped;

  /// The migration that failed, if any (stops the batch).
  final AppliedMigration? failed;

  /// Pending migrations not run because an earlier one failed.
  final List<Migration> notRun;

  const MigrationRunReport({
    required this.applied,
    required this.skipped,
    required this.failed,
    required this.notRun,
  });

  /// True when nothing failed.
  bool get success => failed == null;
}
