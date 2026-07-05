import '../entities/skill_entity.dart';

/// A latest skill found near a query embedding, with its cosine [distance]
/// (lower = more similar). Powers the save-time signal that nudges agents to
/// refine an existing skill (reuse its key) instead of creating a duplicate.
class SkillNeighbor {
  final SkillEntity skill;
  final double distance;

  const SkillNeighbor({required this.skill, required this.distance});
}
