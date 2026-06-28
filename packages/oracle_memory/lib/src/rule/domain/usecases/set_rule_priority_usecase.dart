import 'package:oracle_core/oracle_core.dart';

import '../entities/rule_entity.dart';
import '../errors/rule_failure.dart';
import '../repositories/rule_repository.dart';

/// Re-ranks an existing rule in place (no supersession). Agents use this to
/// raise/lower how strongly a still-valid rule weighs in `rulesForTask`.
abstract interface class SetRulePriorityUsecase {
  AsyncResultDart<RuleEntity, RuleFailure> call(IdVO id, int priority);
}

class SetRulePriorityUsecaseImpl implements SetRulePriorityUsecase {
  final RuleRepository _repository;
  const SetRulePriorityUsecaseImpl(this._repository);

  @override
  AsyncResultDart<RuleEntity, RuleFailure> call(IdVO id, int priority) async {
    final fields = <FieldSystemFailure>[];
    if (id.value.trim().isEmpty) {
      fields.add(const FieldSystemFailure(field: 'id', message: 'Required'));
    }
    if (priority < 0 || priority > 100) {
      fields.add(const FieldSystemFailure(field: 'priority', message: 'Must be 0..100'));
    }
    if (fields.isNotEmpty) {
      return Failure(ValidatedFieldRuleFailure(
        errorMessage: 'Invalid priority update',
        stackTrace: StackTrace.current,
        fields: fields,
      ));
    }
    return _repository.setRulePriority(id, priority);
  }
}
