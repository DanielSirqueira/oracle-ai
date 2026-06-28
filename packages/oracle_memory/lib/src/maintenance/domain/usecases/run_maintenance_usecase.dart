import 'package:oracle_core/oracle_core.dart';

import '../dtos/decay_policy.dart';
import '../dtos/maintenance_report.dart';
import '../errors/maintenance_failure.dart';
import '../repositories/maintenance_repository.dart';

/// Runs the deterministic maintenance sweep (decay + dedup of memories).
abstract interface class RunMaintenanceUsecase {
  AsyncResultDart<MaintenanceReport, MaintenanceFailure> call(DecayPolicy policy);
}

class RunMaintenanceUsecaseImpl implements RunMaintenanceUsecase {
  final MaintenanceRepository _repository;
  const RunMaintenanceUsecaseImpl(this._repository);

  @override
  AsyncResultDart<MaintenanceReport, MaintenanceFailure> call(DecayPolicy policy) =>
      _repository.runMaintenance(policy);
}
