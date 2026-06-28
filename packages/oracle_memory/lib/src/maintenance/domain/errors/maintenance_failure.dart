import 'package:oracle_core/oracle_core.dart';

/// Base failure for the maintenance module.
class MaintenanceFailure extends SystemFailure {
  MaintenanceFailure({
    super.label = 'Maintenance Error',
    required super.errorMessage,
    required super.stackTrace,
    super.fields,
  });
}

class DatasourceMaintenanceFailure extends MaintenanceFailure {
  DatasourceMaintenanceFailure({required super.errorMessage, required super.stackTrace})
      : super(label: 'Maintenance Datasource Error');
}
