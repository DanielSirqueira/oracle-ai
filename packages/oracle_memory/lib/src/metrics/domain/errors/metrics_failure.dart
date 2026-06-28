import 'package:oracle_core/oracle_core.dart';

class MetricsFailure extends SystemFailure {
  MetricsFailure({
    super.label = 'Metrics Error',
    required super.errorMessage,
    required super.stackTrace,
    super.fields,
  });
}

class DatasourceMetricsFailure extends MetricsFailure {
  DatasourceMetricsFailure({required super.errorMessage, required super.stackTrace})
      : super(label: 'Metrics Datasource Error');
}
