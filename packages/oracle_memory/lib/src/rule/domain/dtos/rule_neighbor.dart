import '../entities/rule_entity.dart';

/// A latest rule found near a query embedding, with its cosine [distance]
/// (lower = more similar). Powers the save-time signal that nudges agents to
/// refine an existing rule (reuse its key) instead of creating a duplicate.
class RuleNeighbor {
  final RuleEntity rule;
  final double distance;

  const RuleNeighbor({required this.rule, required this.distance});
}
