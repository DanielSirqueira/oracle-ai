import 'package:oracle_core/oracle_core.dart';

import '../dtos/metric_delta.dart';
import '../dtos/metrics_summary.dart';
import '../entities/session_metric_entity.dart';
import '../errors/metrics_failure.dart';

/// Business contract for the measurement harness.
abstract interface class MetricsRepository {
  /// Adds [delta] to the session's row (upsert + accumulate).
  AsyncResultDart<SessionMetricEntity, MetricsFailure> addMetric(MetricDelta delta);

  /// Aggregate per experiment label (all labels, or just [label]).
  AsyncResultDart<List<MetricsSummary>, MetricsFailure> summary({String? label});

  /// Recent per-session rows for a project.
  AsyncResultDart<List<SessionMetricEntity>, MetricsFailure> recent(IdVO projectId, {int limit});
}
