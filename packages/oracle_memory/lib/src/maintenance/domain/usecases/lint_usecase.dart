import 'package:oracle_core/oracle_core.dart';

import '../dtos/lint_report.dart';
import '../errors/maintenance_failure.dart';
import '../repositories/maintenance_repository.dart';

/// Read-only health check over the memory bank (recall blind spots, demands the
/// agent never answered). Reports; never mutates.
abstract interface class LintUsecase {
  AsyncResultDart<LintReport, MaintenanceFailure> call();
}

class LintUsecaseImpl implements LintUsecase {
  final MaintenanceRepository _repository;
  final Embedder _embedder;
  const LintUsecaseImpl(this._repository, this._embedder);

  @override
  AsyncResultDart<LintReport, MaintenanceFailure> call() =>
      _repository.lint(_embedder.model);
}
