import 'package:oracle_core/oracle_core.dart';

import '../entities/skill_entity.dart';
import '../errors/skill_failure.dart';
import '../repositories/skill_repository.dart';

/// Inventory of the current (latest, non-retired) skills visible to a scope:
/// global + the product's + the project's. Used by listings and by sync-skills.
abstract interface class ListSkillsUsecase {
  AsyncResultDart<List<SkillEntity>, SkillFailure> call({
    IdVO? projectId,
    IdVO? productId,
    int limit,
  });
}

class ListSkillsUsecaseImpl implements ListSkillsUsecase {
  final SkillRepository _repository;
  const ListSkillsUsecaseImpl(this._repository);

  @override
  AsyncResultDart<List<SkillEntity>, SkillFailure> call({
    IdVO? projectId,
    IdVO? productId,
    int limit = 200,
  }) {
    return _repository.listSkills(projectId: projectId, productId: productId, limit: limit);
  }
}
