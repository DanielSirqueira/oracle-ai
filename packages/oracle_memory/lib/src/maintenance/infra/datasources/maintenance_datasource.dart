import '../../domain/dtos/decay_policy.dart';
import '../../domain/dtos/lint_report.dart';
import '../../domain/dtos/maintenance_report.dart';
import '../../domain/dtos/reembed_target.dart';

/// Data-access contract for the maintenance sweep. Implementations **throw**
/// typed failures.
abstract interface class MaintenanceDatasource {
  /// Read-only health check (recall blind spots, leaked sessions, and vectors
  /// whose model differs from [currentModel]).
  Future<LintReport> lint(String currentModel);

  /// Forgets stale, low-value, rarely-accessed memories (or lists candidates
  /// when [DecayPolicy.dryRun]).
  Future<List<MaintenanceItem>> decaySweep(DecayPolicy policy);

  /// Forgets the weaker of near-duplicate memories (or lists candidates when
  /// [DecayPolicy.dryRun]).
  Future<List<MaintenanceItem>> dedupSweep(DecayPolicy policy);

  /// Latest rows whose embedding is missing OR was produced by a model other
  /// than [currentModel], across the embedded tables — the targets a re-embed
  /// pass must refresh. Bounded by [limit].
  Future<List<ReembedTarget>> staleEmbeddingTargets(String currentModel, int limit);

  /// Writes a freshly computed [vector] (produced by [model]) back onto the row
  /// identified by [target].
  Future<void> applyEmbedding(ReembedTarget target, List<double> vector, String model);
}
