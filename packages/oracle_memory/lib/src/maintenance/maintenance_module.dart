import 'package:oracle_core/oracle_core.dart';

import 'domain/repositories/maintenance_repository.dart';
import 'domain/usecases/lint_usecase.dart';
import 'domain/usecases/reembed_usecase.dart';
import 'domain/usecases/run_maintenance_usecase.dart';
import 'external/datasources/database/database_maintenance_datasource.dart';
import 'infra/datasources/maintenance_datasource.dart';
import 'infra/repositories/maintenance_repository_impl.dart';

/// DI bindings for the maintenance feature (deterministic sweep over memories).
/// Requires a `Database` to be registered.
class MaintenanceModule extends Module {
  @override
  void binds(AutoInjector i) {
    i
      ..addLazySingleton<MaintenanceDatasource>(DatabaseMaintenanceDatasource.new)
      ..addLazySingleton<MaintenanceRepository>(MaintenanceRepositoryImpl.new)
      ..addLazySingleton<RunMaintenanceUsecase>(RunMaintenanceUsecaseImpl.new)
      ..addLazySingleton<LintUsecase>(LintUsecaseImpl.new)
      ..addLazySingleton<ReembedUsecase>(ReembedUsecaseImpl.new);
  }
}
