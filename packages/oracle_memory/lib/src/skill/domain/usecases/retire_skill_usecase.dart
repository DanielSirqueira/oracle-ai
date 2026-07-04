import 'package:oracle_core/oracle_core.dart';

import '../entities/skill_entity.dart';
import '../errors/skill_failure.dart';
import '../repositories/skill_repository.dart';

/// Retires a skill that is wrong or obsolete. Soft by default (dropped from
/// recall, kept for audit with a reason); hard permanently deletes it.
abstract interface class RetireSkillUsecase {
  AsyncResultDart<SkillEntity, SkillFailure> call(IdVO id, {String? reason, bool hard});
}

class RetireSkillUsecaseImpl implements RetireSkillUsecase {
  final SkillRepository _repository;
  const RetireSkillUsecaseImpl(this._repository);

  @override
  AsyncResultDart<SkillEntity, SkillFailure> call(IdVO id, {String? reason, bool hard = false}) {
    return _repository.retireSkill(id, reason: reason, hard: hard);
  }
}
