import '../entities/skill_entity.dart';

/// A skill plus its fused relevance [score] from a search.
class SkillSearchResult {
  final SkillEntity skill;

  /// Fused score (e.g. RRF). Higher is more relevant.
  final double score;

  const SkillSearchResult({required this.skill, required this.score});
}
