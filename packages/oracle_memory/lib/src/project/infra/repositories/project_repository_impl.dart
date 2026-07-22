import 'package:oracle_core/oracle_core.dart';

import '../../domain/dtos/filters/project_filter.dart';
import '../../domain/entities/project_entity.dart';
import '../../domain/errors/project_failure.dart';
import '../../domain/repositories/project_repository.dart';
import '../datasources/project_datasource.dart';

/// Bridges the domain contract to the datasource: catches the module's typed
/// `ProjectFailure`s and wraps them in a `ResultDart`.
class ProjectRepositoryImpl implements ProjectRepository {
  final ProjectDatasource _datasource;
  const ProjectRepositoryImpl({required ProjectDatasource datasource})
      : _datasource = datasource;

  @override
  AsyncResultDart<ProjectEntity, ProjectFailure> registerProject(ProjectEntity project) async {
    try {
      return Success(await _datasource.registerProject(project));
    } on ProjectFailure catch (failure) {
      return Failure(failure);
    }
  }

  @override
  AsyncResultDart<ProjectEntity, ProjectFailure> resolveProject(ProjectEntity project) async {
    try {
      return Success(await _datasource.resolveProject(project));
    } on ProjectFailure catch (failure) {
      return Failure(failure);
    }
  }

  @override
  AsyncResultDart<Unit, ProjectFailure> deleteProject(IdVO id) async {
    try {
      await _datasource.deleteProject(id);
      return const Success(unit);
    } on ProjectFailure catch (failure) {
      return Failure(failure);
    }
  }

  @override
  AsyncResultDart<ProjectEntity, ProjectFailure> getProjectById(IdVO id) async {
    try {
      return Success(await _datasource.getProjectById(id));
    } on ProjectFailure catch (failure) {
      return Failure(failure);
    }
  }

  @override
  AsyncResultDart<List<ProjectEntity>, ProjectFailure> listProjects(ProjectFilter filter) async {
    try {
      return Success(await _datasource.listProjects(filter));
    } on ProjectFailure catch (failure) {
      return Failure(failure);
    }
  }
}
