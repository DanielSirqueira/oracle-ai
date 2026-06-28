import '../../domain/dtos/decay_policy.dart';
import '../../domain/dtos/lint_report.dart';
import '../../domain/dtos/maintenance_report.dart';

/// Data-access contract for the maintenance sweep. Implementations **throw**
/// typed failures.
abstract interface class MaintenanceDatasource {
  /// Read-only health check (recall blind spots, leaked sessions).
  Future<LintReport> lint();

  /// Forgets stale, low-value, rarely-accessed memories (or lists candidates
  /// when [DecayPolicy.dryRun]).
  Future<List<MaintenanceItem>> decaySweep(DecayPolicy policy);

  /// Forgets the weaker of near-duplicate memories (or lists candidates when
  /// [DecayPolicy.dryRun]).
  Future<List<MaintenanceItem>> dedupSweep(DecayPolicy policy);
}
