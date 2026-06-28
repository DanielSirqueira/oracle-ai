import 'package:oracle_core/oracle_core.dart';

class HandoffFailure extends SystemFailure {
  HandoffFailure({
    super.label = 'Handoff Error',
    required super.errorMessage,
    required super.stackTrace,
    super.fields,
  });
}

class HandoffNotFoundFailure extends HandoffFailure {
  HandoffNotFoundFailure({required super.stackTrace})
      : super(label: 'Handoff Not Found', errorMessage: 'Handoff not found');
}

class DatasourceHandoffFailure extends HandoffFailure {
  DatasourceHandoffFailure({required super.errorMessage, required super.stackTrace})
      : super(label: 'Handoff Datasource Error');
}

class ValidatedFieldHandoffFailure extends HandoffFailure {
  ValidatedFieldHandoffFailure({
    required super.errorMessage,
    required super.stackTrace,
    required super.fields,
  }) : super(label: 'Handoff Validation Error');
}
