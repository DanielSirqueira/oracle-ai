import 'package:oracle_core/oracle_core.dart';

class AgentSearchFailure extends SystemFailure {
  AgentSearchFailure({
    super.label = 'Agent Search Error',
    required super.errorMessage,
    required super.stackTrace,
    super.fields,
  });
}

class DatasourceAgentSearchFailure extends AgentSearchFailure {
  DatasourceAgentSearchFailure({required super.errorMessage, required super.stackTrace})
      : super(label: 'Agent Search Datasource Error');
}
