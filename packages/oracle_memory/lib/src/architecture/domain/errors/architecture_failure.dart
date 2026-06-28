import 'package:oracle_core/oracle_core.dart';

class ArchitectureFailure extends SystemFailure {
  ArchitectureFailure({
    super.label = 'Architecture Error',
    required super.errorMessage,
    required super.stackTrace,
    super.fields,
  });
}

class ArchitectureNotFoundFailure extends ArchitectureFailure {
  ArchitectureNotFoundFailure({required super.stackTrace})
      : super(label: 'Architecture Not Found', errorMessage: 'Architecture not found');
}

class DatasourceArchitectureFailure extends ArchitectureFailure {
  DatasourceArchitectureFailure({required super.errorMessage, required super.stackTrace})
      : super(label: 'Architecture Datasource Error');
}

class ValidatedFieldArchitectureFailure extends ArchitectureFailure {
  ValidatedFieldArchitectureFailure({
    required super.errorMessage,
    required super.stackTrace,
    required super.fields,
  }) : super(label: 'Architecture Validation Error');
}
