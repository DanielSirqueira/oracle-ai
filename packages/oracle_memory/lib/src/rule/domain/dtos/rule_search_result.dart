import '../entities/rule_entity.dart';

/// A rule plus its fused relevance [score] from a search.
class RuleSearchResult {
  final RuleEntity rule;
  final double score;

  const RuleSearchResult({required this.rule, required this.score});
}
