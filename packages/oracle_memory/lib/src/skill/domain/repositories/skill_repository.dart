import 'package:oracle_core/oracle_core.dart';

import '../dtos/filters/skill_search_filter.dart';
import '../dtos/skill_neighbor.dart';
import '../dtos/skill_search_result.dart';
import '../entities/skill_entity.dart';
import '../errors/skill_failure.dart';

/// Business contract for the shared skill library.
abstract interface class SkillRepository {
  /// Saves a skill, superseding any current version with the same key in the
  /// same owner (project, organization, or global).
  AsyncResultDart<SkillEntity, SkillFailure> saveSkill(SkillEntity skill);

  /// Latest skills near [embedding] (same owner + model), excluding [excludeId]
  /// — the save-time near-duplicate signal. A failed lookup degrades to an empty
  /// list, so it is a plain optional, not a Result.
  Future<List<SkillNeighbor>> nearestByEmbedding({
    IdVO? organizationId,
    IdVO? projectId,
    IdVO? moduleId,
    required List<double> embedding,
    required String embeddingModel,
    IdVO? excludeId,
    double maxDistance,
    int limit,
  });

  /// The current (is_latest) skill with [key] in the given owner, or null when
  /// none exists. Used to short-circuit an unchanged re-save before embedding.
  /// A failed lookup degrades to null (the caller just performs a normal save).
  Future<SkillEntity?> currentByKey({
    IdVO? organizationId,
    IdVO? projectId,
    IdVO? moduleId,
    required String key,
  });

  AsyncResultDart<SkillEntity, SkillFailure> getSkillById(IdVO id);

  /// Resolves [key] with override semantics: the project's version wins over
  /// the organization's, which wins over the global one.
  AsyncResultDart<SkillEntity, SkillFailure> getSkillByKey(
    String key, {
    IdVO? projectId,
    IdVO? organizationId,
    IdVO? moduleId,
  });

  /// Hybrid search over the library (vector + full-text, RRF). Always includes
  /// global skills; project/organization narrow the additional scope.
  AsyncResultDart<List<SkillSearchResult>, SkillFailure> searchSkills(SkillSearchFilter filter);

  /// Current (latest, non-retired) skills visible to the given scope.
  AsyncResultDart<List<SkillEntity>, SkillFailure> listSkills({
    IdVO? projectId,
    IdVO? organizationId,
    int limit,
  });

  /// Retires a skill: soft by default (dropped from recall, kept for audit),
  /// or permanently removed when [hard] is true.
  AsyncResultDart<SkillEntity, SkillFailure> retireSkill(
    IdVO id, {
    String? reason,
    bool hard,
  });
}
