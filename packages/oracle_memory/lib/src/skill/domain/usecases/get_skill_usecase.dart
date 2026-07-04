import 'package:oracle_core/oracle_core.dart';

import '../entities/skill_entity.dart';
import '../errors/skill_failure.dart';
import '../repositories/skill_repository.dart';

/// Loads one skill's full content (progressive disclosure: searches return
/// name+description; this is the "load the skill" step). Accepts an [id] or a
/// [key] — a key resolves project → product → global (override semantics).
abstract interface class GetSkillUsecase {
  AsyncResultDart<SkillEntity, SkillFailure> call({
    IdVO? id,
    String? key,
    IdVO? projectId,
    IdVO? productId,
  });
}

class GetSkillUsecaseImpl implements GetSkillUsecase {
  final SkillRepository _repository;
  const GetSkillUsecaseImpl(this._repository);

  @override
  AsyncResultDart<SkillEntity, SkillFailure> call({
    IdVO? id,
    String? key,
    IdVO? projectId,
    IdVO? productId,
  }) async {
    if (id != null && id.value.trim().isNotEmpty) {
      return _repository.getSkillById(id);
    }
    if (key != null && key.trim().isNotEmpty) {
      return _repository.getSkillByKey(key.trim(), projectId: projectId, productId: productId);
    }
    return Failure(ValidatedFieldSkillFailure(
      errorMessage: 'Invalid lookup',
      stackTrace: StackTrace.current,
      fields: const [FieldSystemFailure(field: 'id|key', message: 'Pass an id or a key')],
    ));
  }
}
