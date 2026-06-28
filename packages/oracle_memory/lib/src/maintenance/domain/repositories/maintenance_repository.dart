import 'package:oracle_core/oracle_core.dart';

import '../dtos/decay_policy.dart';
import '../dtos/lint_report.dart';
import '../dtos/maintenance_report.dart';
import '../errors/maintenance_failure.dart';

/// Business contract for the deterministic maintenance sweep.
abstract interface class MaintenanceRepository {
  /// Runs the decay and/or dedup passes per [policy], returning what was
  /// (or would be, in dry-run) forgotten.
  AsyncResultDart<MaintenanceReport, MaintenanceFailure> runMaintenance(DecayPolicy policy);

  /// Read-only health check (recall blind spots, leaked sessions).
  AsyncResultDart<LintReport, MaintenanceFailure> lint();
}
