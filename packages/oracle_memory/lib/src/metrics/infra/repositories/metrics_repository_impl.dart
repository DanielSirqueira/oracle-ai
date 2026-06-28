import 'package:oracle_core/oracle_core.dart';

import '../../domain/dtos/metric_delta.dart';
import '../../domain/dtos/metrics_summary.dart';
import '../../domain/entities/session_metric_entity.dart';
import '../../domain/errors/metrics_failure.dart';
import '../../domain/repositories/metrics_repository.dart';
import '../datasources/metrics_datasource.dart';

class MetricsRepositoryImpl implements MetricsRepository {
  final MetricsDatasource _datasource;
  const MetricsRepositoryImpl({required MetricsDatasource datasource}) : _datasource = datasource;

  @override
  AsyncResultDart<SessionMetricEntity, MetricsFailure> addMetric(MetricDelta delta) async {
    try {
      return Success(await _datasource.addMetric(delta));
    } on MetricsFailure catch (failure) {
      return Failure(failure);
    }
  }

  @override
  AsyncResultDart<List<MetricsSummary>, MetricsFailure> summary({String? label}) async {
    try {
      return Success(await _datasource.summary(label: label));
    } on MetricsFailure catch (failure) {
      return Failure(failure);
    }
  }

  @override
  AsyncResultDart<List<SessionMetricEntity>, MetricsFailure> recent(
    IdVO projectId, {
    int limit = 20,
  }) async {
    try {
      return Success(await _datasource.recent(projectId, limit: limit));
    } on MetricsFailure catch (failure) {
      return Failure(failure);
    }
  }
}
