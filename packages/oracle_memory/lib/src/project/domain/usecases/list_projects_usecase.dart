import 'package:oracle_core/oracle_core.dart';

import '../dtos/filters/project_filter.dart';
import '../entities/project_entity.dart';
import '../errors/project_failure.dart';
import '../repositories/project_repository.dart';

/// Lists projects matching a filter.
abstract interface class ListProjectsUsecase {
  AsyncResultDart<List<ProjectEntity>, ProjectFailure> call(ProjectFilter filter);
}

class ListProjectsUsecaseImpl implements ListProjectsUsecase {
  final ProjectRepository _repository;
  const ListProjectsUsecaseImpl(this._repository);

  @override
  AsyncResultDart<List<ProjectEntity>, ProjectFailure> call(ProjectFilter filter) =>
      _repository.listProjects(filter);
}
