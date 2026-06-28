/// State of a migration row in `_migrations`.
enum MigrationStatus {
  /// Running. The transaction has not committed yet.
  running,

  /// Applied successfully.
  applied,

  /// Failed during execution. DDL/DML rolled back, but the row persists (with
  /// an error message) for diagnostics.
  failed;

  /// Parses the `status` column string into the enum.
  static MigrationStatus parse(String code) {
    return values.firstWhere(
      (s) => s.name == code,
      orElse: () => throw ArgumentError('Unknown status: $code'),
    );
  }
}
