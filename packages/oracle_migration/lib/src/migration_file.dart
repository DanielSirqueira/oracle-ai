/// A single SQL file inside a migration.
///
/// One atomic step within a logical migration — all files of a migration run
/// together inside one transaction.
class MigrationFile {
  /// Sequence number of the file (e.g. `'001'`, `'010'`). Orders within a
  /// migration.
  final String sequence;

  /// Full file name, e.g. `'001_create_tables.sql'`.
  final String name;

  /// Absolute file path.
  final String path;

  /// SQL content.
  final String content;

  const MigrationFile({
    required this.sequence,
    required this.name,
    required this.path,
    required this.content,
  });
}
