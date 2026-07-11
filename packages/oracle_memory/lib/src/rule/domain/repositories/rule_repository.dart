import 'package:oracle_core/oracle_core.dart';

import '../dtos/filters/rule_search_filter.dart';
import '../dtos/rule_neighbor.dart';
import '../dtos/rule_search_result.dart';
import '../dtos/rules_for_task_query.dart';
import '../entities/rule_entity.dart';
import '../errors/rule_failure.dart';

/// Business contract for development rules.
abstract interface class RuleRepository {
  /// Saves a rule, superseding any current rule with the same key in the same
  /// scope owner (organization or project).
  AsyncResultDart<RuleEntity, RuleFailure> saveRule(RuleEntity rule);

  /// The current (is_latest) rule with [key] in the given owner, or null when
  /// none exists. Used to short-circuit an unchanged re-save before embedding.
  /// A failed lookup degrades to null (the caller just performs a normal save).
  Future<RuleEntity?> currentByKey({
    IdVO? organizationId,
    IdVO? projectId,
    required String key,
  });

  /// Latest rules near [embedding] (same owner + model), excluding [excludeId]
  /// — the save-time near-duplicate signal. Non-critical: a failed lookup
  /// degrades to an empty list.
  Future<List<RuleNeighbor>> nearestByEmbedding({
    IdVO? organizationId,
    IdVO? projectId,
    required List<double> embedding,
    required String embeddingModel,
    IdVO? excludeId,
    double? maxDistance,
    int? limit,
  });

  /// Applicable rules for a task, resolving organization→project inheritance and
  /// override (project rules win over organization rules with the same key).
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
