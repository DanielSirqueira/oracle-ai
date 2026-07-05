import 'package:oracle_core/oracle_core.dart';

import '../dtos/filters/skill_search_filter.dart';
import '../dtos/skill_search_result.dart';
import '../entities/skill_entity.dart';
import '../errors/skill_failure.dart';

/// Business contract for the shared skill library.
abstract interface class SkillRepository {
  /// Saves a skill, superseding any current version with the same key in the
  /// same owner (project, product, or global).
  AsyncResultDart<SkillEntity, SkillFailure> saveSkill(SkillEntity skill);

  /// The current (is_latest) skill with [key] in the given owner, or null when
  /// none exists. Used to short-circuit an unchanged re-save before embedding.
  /// A failed lookup degrades to null (the caller just performs a normal save).
  Future<SkillEntity?> currentByKey({
    IdVO? productId,
    IdVO? projectId,
    required String key,
  });

  AsyncResultDart<SkillEntity, SkillFailure> getSkillById(IdVO id);

  /// Resolves [key] with override semantics: the project's version wins over
  /// the product's, which wins over the global one.
  AsyncResultDart<SkillEntity, SkillFailure> getSkillByKey(
    String key, {
    IdVO? projectId,
    IdVO? productId,
  });

  /// Hybrid search over the library (vector + full-text, RRF). Always includes
  /// global skills; project/product narrow the additional scope.
  AsyncResultDart<List<SkillSearchResult>, SkillFailure> searchSkills(SkillSearchFilter filter);

  /// Current (latest, non-retired) skills visible to the given scope.
  AsyncResultDart<List<SkillEntity>, SkillFailure> listSkills({
    IdVO? projectId,
    IdVO? productId,
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
