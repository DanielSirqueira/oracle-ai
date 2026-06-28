import 'package:oracle_core/oracle_core.dart';

import '../../domain/dtos/filters/rule_search_filter.dart';
import '../../domain/dtos/rule_search_result.dart';
import '../../domain/dtos/rules_for_task_query.dart';
import '../../domain/entities/rule_entity.dart';

/// Data-access contract for rules. Implementations **throw** typed failures.
abstract interface class RuleDatasource {
  Future<RuleEntity> saveRule(RuleEntity rule);

  Future<List<RuleEntity>> rulesForTask(RulesForTaskQuery query);

  Future<List<RuleSearchResult>> searchRules(RuleSearchFilter filter);

  /// Soft-retires a rule (drops it from recall, keeps history) or, when [hard],
  /// permanently deletes it. Returns the affected rule.
  Future<RuleEntity> retireRule(IdVO id, {String? reason, bool hard});

  /// Re-ranks a rule in place (lightweight; no supersession).
  Future<RuleEntity> setRulePriority(IdVO id, int priority);
}
