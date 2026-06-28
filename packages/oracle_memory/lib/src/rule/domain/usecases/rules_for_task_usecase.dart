import 'package:oracle_core/oracle_core.dart';

import '../dtos/rules_for_task_query.dart';
import '../entities/rule_entity.dart';
import '../errors/rule_failure.dart';
import '../repositories/rule_repository.dart';

/// Returns the rules that apply to a task (inheritance + override), so the
/// agent can consult them before generating code.
abstract interface class RulesForTaskUsecase {
  AsyncResultDart<List<RuleEntity>, RuleFailure> call(RulesForTaskQuery query);
}

class RulesForTaskUsecaseImpl implements RulesForTaskUsecase {
  final RuleRepository _repository;
  const RulesForTaskUsecaseImpl(this._repository);

  @override
  AsyncResultDart<List<RuleEntity>, RuleFailure> call(RulesForTaskQuery query) =>
      _repository.rulesForTask(query);
}
