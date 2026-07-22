import 'package:oracle_core/oracle_core.dart';

/// Base failure for the Loop Engineering (flow) module.
class FlowFailure extends SystemFailure {
  FlowFailure({
    super.label = 'Flow Error',
    required super.errorMessage,
    required super.stackTrace,
    super.fields,
  });
}

class FlowNotFoundFailure extends FlowFailure {
  FlowNotFoundFailure({required super.stackTrace})
    : super(label: 'Flow Not Found', errorMessage: 'Flow not found');
}

class DatasourceFlowFailure extends FlowFailure {
  DatasourceFlowFailure({
    required super.errorMessage,
    required super.stackTrace,
  }) : super(label: 'Flow Datasource Error');
}

class ValidatedFieldFlowFailure extends FlowFailure {
  ValidatedFieldFlowFailure({
    required super.errorMessage,
    required super.stackTrace,
    required super.fields,
  }) : super(label: 'Flow Validation Error');
}
