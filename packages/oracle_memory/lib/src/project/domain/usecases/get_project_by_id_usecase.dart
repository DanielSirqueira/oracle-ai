import 'package:oracle_core/oracle_core.dart';

import '../entities/project_entity.dart';
import '../errors/project_failure.dart';
import '../repositories/project_repository.dart';

/// Fetches a project by its id.
abstract interface class GetProjectByIdUsecase {
  AsyncResultDart<ProjectEntity, ProjectFailure> call(IdVO id);
}

class GetProjectByIdUsecaseImpl implements GetProjectByIdUsecase {
  final ProjectRepository _repository;
  const GetProjectByIdUsecaseImpl(this._repository);

  @override
  AsyncResultDart<ProjectEntity, ProjectFailure> call(IdVO id) =>
      _repository.getProjectById(id);
}
