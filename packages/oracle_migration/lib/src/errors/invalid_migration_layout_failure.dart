import 'migration_failure.dart';

/// Raised when the migrations directory layout is invalid (bad version folder,
/// bad migration folder, missing SQL files, duplicate sequence numbers, ...).
class InvalidMigrationLayoutFailure extends MigrationFailure {
  /// Path that triggered the failure.
  final String path;

  InvalidMigrationLayoutFailure({
    required super.errorMessage,
    required this.path,
    required super.stackTrace,
  }) : super(label: 'Invalid Migration Layout');
}
