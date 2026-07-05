import 'package:oracle_core/oracle_core.dart';

import '../../domain/dtos/filters/skill_search_filter.dart';
import '../../domain/dtos/skill_neighbor.dart';
import '../../domain/dtos/skill_search_result.dart';
import '../../domain/entities/skill_entity.dart';

/// Data-access contract for skills. Implementations **throw** typed failures;
/// the repository wraps them in a `ResultDart`.
abstract interface class SkillDatasource {
  Future<SkillEntity> saveSkill(SkillEntity skill);

  /// Latest skills near [embedding] in the same owner (same model), excluding
  /// [excludeId] — the save-time near-duplicate signal.
  Future<List<SkillNeighbor>> nearestByEmbedding({
    IdVO? productId,
    IdVO? projectId,
    required List<double> embedding,
    required String embeddingModel,
    IdVO? excludeId,
    double maxDistance,
    int limit,
  });

  /// The current (is_latest) skill with [key] in the given owner (project,
  /// product, or global when both ids are null), or null.
  Future<SkillEntity?> currentByKey({IdVO? productId, IdVO? projectId, required String key});

  /// Reads by id and bumps the usage substrate (access_count/last_accessed_at).
  Future<SkillEntity> getSkillById(IdVO id);

  /// Resolves [key] project → product → global (override semantics) and bumps
  /// the usage substrate of the resolved row.
  Future<SkillEntity> getSkillByKey(String key, {IdVO? projectId, IdVO? productId});

  Future<List<SkillSearchResult>> searchSkills(SkillSearchFilter filter);

  Future<List<SkillEntity>> listSkills({IdVO? projectId, IdVO? productId, int limit});

  Future<SkillEntity> retireSkill(IdVO id, {String? reason, bool hard});
}
