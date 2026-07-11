import 'package:oracle_core/oracle_core.dart';

import '../../domain/dtos/filters/rule_search_filter.dart';
import '../../domain/dtos/rule_neighbor.dart';
import '../../domain/dtos/rule_search_result.dart';
import '../../domain/dtos/rules_for_task_query.dart';
import '../../domain/entities/rule_entity.dart';

/// Data-access contract for rules. Implementations **throw** typed failures.
abstract interface class RuleDatasource {
  Future<RuleEntity> saveRule(RuleEntity rule);

  /// The current (is_latest) rule with [key] in the given owner, or null.
  /// Lets a save skip re-embedding + re-inserting when nothing changed.
  Future<RuleEntity?> currentByKey({IdVO? organizationId, IdVO? projectId, required String key});

  /// Latest rules in the same owner within [maxDistance] cosine distance of
  /// [embedding] (same model only), excluding [excludeId]. Backs the save-time
  /// near-duplicate signal. Empty when nothing is close enough.
  Future<List<RuleNeighbor>> nearestByEmbedding({
    IdVO? organizationId,
    IdVO? projectId,
    required List<double> embedding,
    required String embeddingModel,
    IdVO? excludeId,
    double? maxDistance,
    int? limit,
  });

  Future<List<RuleEntity>> rulesForTask(RulesForTaskQuery query);

  Future<List<RuleSearchResult>> searchRules(RuleSearchFilter filter);

  /// Soft-retires a rule (drops it from recall, keeps history) or, when [hard],
  /// permanently deletes it. Returns the affected rule.
  Future<RuleEntity> retireRule(IdVO id, {String? reason, bool hard});

  /// Re-ranks a rule in place (lightweight; no supersession).
  Future<RuleEntity> setRulePriority(IdVO id, int priority);
}
