import 'package:oracle_core/oracle_core.dart';

/// Base failure for the rule module.
class RuleFailure extends SystemFailure {
  RuleFailure({
    super.label = 'Rule Error',
    required super.errorMessage,
    required super.stackTrace,
    super.fields,
  });
}

class RuleNotFoundFailure extends RuleFailure {
  RuleNotFoundFailure({required super.stackTrace})
      : super(label: 'Rule Not Found', errorMessage: 'Rule not found');
}

class DatasourceRuleFailure extends RuleFailure {
  DatasourceRuleFailure({required super.errorMessage, required super.stackTrace})
      : super(label: 'Rule Datasource Error');
}

class ValidatedFieldRuleFailure extends RuleFailure {
  ValidatedFieldRuleFailure({
    required super.errorMessage,
    required super.stackTrace,
    required super.fields,
  }) : super(label: 'Rule Validation Error');
}
