import 'package:oracle_core/oracle_core.dart';

import '../dtos/metric_delta.dart';
import '../entities/session_metric_entity.dart';
import '../errors/metrics_failure.dart';
import '../repositories/metrics_repository.dart';

/// Accumulates a metric delta onto a session row.
abstract interface class AddSessionMetricUsecase {
  AsyncResultDart<SessionMetricEntity, MetricsFailure> call(MetricDelta delta);
}

class AddSessionMetricUsecaseImpl implements AddSessionMetricUsecase {
  final MetricsRepository _repository;
  const AddSessionMetricUsecaseImpl(this._repository);

  @override
  AsyncResultDart<SessionMetricEntity, MetricsFailure> call(MetricDelta delta) =>
      _repository.addMetric(delta);
}
