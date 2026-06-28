import 'package:oracle_core/oracle_core.dart';

import '../../domain/dtos/metric_delta.dart';
import '../../domain/dtos/metrics_summary.dart';
import '../../domain/entities/session_metric_entity.dart';

/// Data-access contract for the measurement harness. Implementations **throw**
/// typed failures.
abstract interface class MetricsDatasource {
  Future<SessionMetricEntity> addMetric(MetricDelta delta);

  Future<List<MetricsSummary>> summary({String? label});

  Future<List<SessionMetricEntity>> recent(IdVO projectId, {int limit});
}
