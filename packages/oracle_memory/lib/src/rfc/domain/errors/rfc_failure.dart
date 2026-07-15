import 'package:oracle_core/oracle_core.dart';

/// Base failure for the RFC module.
class RfcFailure extends SystemFailure {
  RfcFailure({
    super.label = 'RFC Error',
    required super.errorMessage,
    required super.stackTrace,
    super.fields,
  });
}

class RfcNotFoundFailure extends RfcFailure {
  RfcNotFoundFailure({required super.stackTrace})
      : super(label: 'RFC Not Found', errorMessage: 'RFC not found');
}

class DatasourceRfcFailure extends RfcFailure {
  DatasourceRfcFailure({required super.errorMessage, required super.stackTrace})
      : super(label: 'RFC Datasource Error');
}

class ValidatedFieldRfcFailure extends RfcFailure {
  ValidatedFieldRfcFailure({
    required super.errorMessage,
    required super.stackTrace,
    required super.fields,
  }) : super(label: 'RFC Validation Error');
}
