import 'package:oracle_core/oracle_core.dart';

import '../../domain/dtos/filters/project_filter.dart';
import '../../domain/entities/project_entity.dart';

/// Data-access contract for projects. Implementations **throw** typed failures
/// (e.g. `DatasourceProjectFailure`, `ProjectNotFoundFailure`); the repository
/// converts them into a `ResultDart`.
abstract interface class ProjectDatasource {
  Future<ProjectEntity> registerProject(ProjectEntity project);

  /// Get-or-create a project by its `repo_path` (race-safe upsert). The agent's
  /// cwd maps to a stable project; an existing one is returned unchanged.
  Future<ProjectEntity> resolveProject(ProjectEntity project);

  Future<ProjectEntity> getProjectById(IdVO id);

  Future<List<ProjectEntity>> listProjects(ProjectFilter filter);

  Future<void> deleteProject(IdVO id);
}
