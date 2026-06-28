import 'package:oracle_core/oracle_core.dart';

import '../entities/session_metric_entity.dart';
import '../errors/metrics_failure.dart';
import '../repositories/metrics_repository.dart';

/// Recent per-session metric rows for a project.
abstract interface class RecentMetricsUsecase {
  AsyncResultDart<List<SessionMetricEntity>, MetricsFailure> call(IdVO projectId, {int limit});
}

class RecentMetricsUsecaseImpl implements RecentMetricsUsecase {
  final MetricsRepository _repository;
  const RecentMetricsUsecaseImpl(this._repository);

  @override
  AsyncResultDart<List<SessionMetricEntity>, MetricsFailure> call(IdVO projectId, {int limit = 20}) =>
      _repository.recent(projectId, limit: limit);
}
