import 'package:oracle_core/oracle_core.dart';

import '../entities/project_entity.dart';
import '../errors/project_failure.dart';
import '../repositories/project_repository.dart';

/// Registers a new project after validating it.
abstract interface class RegisterProjectUsecase {
  AsyncResultDart<ProjectEntity, ProjectFailure> call(ProjectEntity project);
}

class RegisterProjectUsecaseImpl implements RegisterProjectUsecase {
  final ProjectRepository _repository;
  const RegisterProjectUsecaseImpl(this._repository);

  @override
  AsyncResultDart<ProjectEntity, ProjectFailure> call(ProjectEntity project) async {
    if (project.name.isBlank) {
      return Failure(ValidatedFieldProjectFailure(
        errorMessage: 'Project name is required',
        stackTrace: StackTrace.current,
        fields: const [FieldSystemFailure(field: 'name', message: 'Required')],
      ));
    }
    return _repository.registerProject(project);
  }
}
