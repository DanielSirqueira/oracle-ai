import 'package:oracle_core/oracle_core.dart';

import 'domain/repositories/metrics_repository.dart';
import 'domain/usecases/add_session_metric_usecase.dart';
import 'domain/usecases/metrics_summary_usecase.dart';
import 'domain/usecases/recent_metrics_usecase.dart';
import 'external/datasources/database/database_metrics_datasource.dart';
import 'infra/datasources/metrics_datasource.dart';
import 'infra/repositories/metrics_repository_impl.dart';

/// DI bindings for the measurement harness. Requires a `Database`.
class MetricsModule extends Module {
  @override
  void binds(AutoInjector i) {
    i
      ..addLazySingleton<MetricsDatasource>(DatabaseMetricsDatasource.new)
      ..addLazySingleton<MetricsRepository>(MetricsRepositoryImpl.new)
      ..addLazySingleton<AddSessionMetricUsecase>(AddSessionMetricUsecaseImpl.new)
      ..addLazySingleton<MetricsSummaryUsecase>(MetricsSummaryUsecaseImpl.new)
      ..addLazySingleton<RecentMetricsUsecase>(RecentMetricsUsecaseImpl.new);
  }
}
