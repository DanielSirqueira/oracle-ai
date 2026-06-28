import 'package:oracle_core/oracle_core.dart';

import '../dtos/metrics_summary.dart';
import '../errors/metrics_failure.dart';
import '../repositories/metrics_repository.dart';

/// Aggregate metrics per experiment label — the A/B comparison.
abstract interface class MetricsSummaryUsecase {
  AsyncResultDart<List<MetricsSummary>, MetricsFailure> call({String? label});
}

class MetricsSummaryUsecaseImpl implements MetricsSummaryUsecase {
  final MetricsRepository _repository;
  const MetricsSummaryUsecaseImpl(this._repository);

  @override
  AsyncResultDart<List<MetricsSummary>, MetricsFailure> call({String? label}) =>
      _repository.summary(label: label);
}
