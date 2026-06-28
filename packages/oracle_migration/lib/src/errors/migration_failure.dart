import 'package:oracle_core/oracle_core.dart';

/// Base failure for the migration system.
class MigrationFailure extends SystemFailure {
  MigrationFailure({
    required super.errorMessage,
    required super.stackTrace,
    super.label = 'Migration Failure',
    super.fields,
  });
}
