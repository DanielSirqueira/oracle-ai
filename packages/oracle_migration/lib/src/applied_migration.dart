import 'migration_status.dart';

/// A row of the `_migrations` table — a migration that was attempted (or
/// applied) at some point.
class AppliedMigration {
  final int id;
  final String version;
  final String sequence;
  final String name;
  final String checksum;
  final int fileCount;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final MigrationStatus status;
  final String? errorMessage;

  /// Name of the file that failed, when [status] == [MigrationStatus.failed].
  final String? errorFile;

  const AppliedMigration({
    required this.id,
    required this.version,
    required this.sequence,
    required this.name,
    required this.checksum,
    required this.fileCount,
    required this.startedAt,
    required this.finishedAt,
    required this.status,
    required this.errorMessage,
    required this.errorFile,
  });

  /// Unique id — `v1.0.0/001_baseline`.
  String get migrationId => 'v$version/${sequence}_$name';
}
