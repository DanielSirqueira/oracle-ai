import 'package:oracle_core/oracle_core.dart';

/// Base failure for the skill module.
class SkillFailure extends SystemFailure {
  SkillFailure({
    super.label = 'Skill Error',
    required super.errorMessage,
    required super.stackTrace,
    super.fields,
  });
}

class SkillNotFoundFailure extends SkillFailure {
  SkillNotFoundFailure({required super.stackTrace})
      : super(label: 'Skill Not Found', errorMessage: 'Skill not found');
}

class DatasourceSkillFailure extends SkillFailure {
  DatasourceSkillFailure({required super.errorMessage, required super.stackTrace})
      : super(label: 'Skill Datasource Error');
}

class ValidatedFieldSkillFailure extends SkillFailure {
  ValidatedFieldSkillFailure({
    required super.errorMessage,
    required super.stackTrace,
    required super.fields,
  }) : super(label: 'Skill Validation Error');
}
