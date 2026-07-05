import 'package:oracle_core/oracle_core.dart';

import '../dtos/decay_policy.dart';
import '../dtos/lint_report.dart';
import '../dtos/maintenance_report.dart';
import '../dtos/reembed_target.dart';
import '../errors/maintenance_failure.dart';

/// Business contract for the deterministic maintenance sweep.
abstract interface class MaintenanceRepository {
  /// Runs the decay and/or dedup passes per [policy], returning what was
  /// (or would be, in dry-run) forgotten.
  AsyncResultDart<MaintenanceReport, MaintenanceFailure> runMaintenance(DecayPolicy policy);

  /// Read-only health check (recall blind spots, leaked sessions, vectors whose
  /// model differs from [currentModel]).
  AsyncResultDart<LintReport, MaintenanceFailure> lint(String currentModel);

  /// Latest rows whose embedding is missing or was produced by a model other
  /// than [currentModel] (bounded by [limit]) — the re-embed work-list.
  AsyncResultDart<List<ReembedTarget>, MaintenanceFailure> staleEmbeddingTargets(
    String currentModel,
    int limit,
  );

  /// Writes a freshly computed [vector] (from [model]) back onto [target]'s row.
  AsyncResultDart<ReturnVoid, MaintenanceFailure> applyEmbedding(
    ReembedTarget target,
    List<double> vector,
    String model,
  );
}
