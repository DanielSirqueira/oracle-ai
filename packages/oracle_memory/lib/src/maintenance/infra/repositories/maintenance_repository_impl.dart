import 'package:oracle_core/oracle_core.dart';

import '../../domain/dtos/decay_policy.dart';
import '../../domain/dtos/lint_report.dart';
import '../../domain/dtos/maintenance_report.dart';
import '../../domain/errors/maintenance_failure.dart';
import '../../domain/repositories/maintenance_repository.dart';
import '../datasources/maintenance_datasource.dart';

class MaintenanceRepositoryImpl implements MaintenanceRepository {
  final MaintenanceDatasource _datasource;
  const MaintenanceRepositoryImpl({required MaintenanceDatasource datasource})
      : _datasource = datasource;

  @override
  AsyncResultDart<MaintenanceReport, MaintenanceFailure> runMaintenance(DecayPolicy policy) async {
    try {
      // Decay first, then dedup, so dedup sees the post-decay set.
      final decayed = policy.runDecay ? await _datasource.decaySweep(policy) : const <MaintenanceItem>[];
      final deduped = policy.runDedup ? await _datasource.dedupSweep(policy) : const <MaintenanceItem>[];
      return Success(MaintenanceReport(dryRun: policy.dryRun, decayed: decayed, deduped: deduped));
    } on MaintenanceFailure catch (failure) {
      return Failure(failure);
    }
  }

  @override
  AsyncResultDart<LintReport, MaintenanceFailure> lint() async {
    try {
      return Success(await _datasource.lint());
    } on MaintenanceFailure catch (failure) {
      return Failure(failure);
    }
  }
}
