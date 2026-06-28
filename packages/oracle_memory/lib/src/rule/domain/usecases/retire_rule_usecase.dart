import 'package:oracle_core/oracle_core.dart';

import '../entities/rule_entity.dart';
import '../errors/rule_failure.dart';
import '../repositories/rule_repository.dart';

/// Retires a rule that no longer applies. Soft by default (the rule is dropped
/// from recall but kept for audit, with a [reason]); [hard] purges it entirely.
abstract interface class RetireRuleUsecase {
  AsyncResultDart<RuleEntity, RuleFailure> call(IdVO id, {String? reason, bool hard});
}

class RetireRuleUsecaseImpl implements RetireRuleUsecase {
  final RuleRepository _repository;
  const RetireRuleUsecaseImpl(this._repository);

  @override
  AsyncResultDart<RuleEntity, RuleFailure> call(
    IdVO id, {
    String? reason,
    bool hard = false,
  }) async {
    if (id.value.trim().isEmpty) {
      return Failure(ValidatedFieldRuleFailure(
        errorMessage: 'Invalid rule id',
        stackTrace: StackTrace.current,
        fields: const [FieldSystemFailure(field: 'id', message: 'Required')],
      ));
    }
    return _repository.retireRule(id, reason: reason, hard: hard);
  }
}
