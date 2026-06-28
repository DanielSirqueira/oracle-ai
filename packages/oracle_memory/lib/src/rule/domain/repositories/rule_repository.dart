import 'package:oracle_core/oracle_core.dart';

import '../dtos/filters/rule_search_filter.dart';
import '../dtos/rule_search_result.dart';
import '../dtos/rules_for_task_query.dart';
import '../entities/rule_entity.dart';
import '../errors/rule_failure.dart';

/// Business contract for development rules.
abstract interface class RuleRepository {
  /// Saves a rule, superseding any current rule with the same key in the same
  /// scope owner (product or project).
  AsyncResultDart<RuleEntity, RuleFailure> saveRule(RuleEntity rule);

  /// Applicable rules for a task, resolving product→project inheritance and
  /// override (project rules win over product rules with the same key).
  AsyncResultDart<List<RuleEntity>, RuleFailure> rulesForTask(RulesForTaskQuery query);

  /// Hybrid search over rules (vector + full-text, RRF).
  AsyncResultDart<List<RuleSearchResult>, RuleFailure> searchRules(RuleSearchFilter filter);

  /// Retires a rule: soft by default (dropped from recall, kept for audit),
  /// or permanently removed when [hard] is true.
  AsyncResultDart<RuleEntity, RuleFailure> retireRule(
    IdVO id, {
    String? reason,
    bool hard,
  });

  /// Re-ranks a rule in place (new [priority]), without superseding it.
  AsyncResultDart<RuleEntity, RuleFailure> setRulePriority(IdVO id, int priority);
}
