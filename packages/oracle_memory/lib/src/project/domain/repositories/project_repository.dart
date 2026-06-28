import 'package:oracle_core/oracle_core.dart';

import '../dtos/filters/project_filter.dart';
import '../entities/project_entity.dart';
import '../errors/project_failure.dart';

/// Business contract for project persistence. Returns a [ResultDart] of the
/// entity or a typed [ProjectFailure].
abstract interface class ProjectRepository {
  AsyncResultDart<ProjectEntity, ProjectFailure> registerProject(ProjectEntity project);

  /// Get-or-create a project by its `repo_path` (the agent's cwd).
  AsyncResultDart<ProjectEntity, ProjectFailure> resolveProject(ProjectEntity project);

  AsyncResultDart<ProjectEntity, ProjectFailure> getProjectById(IdVO id);

  AsyncResultDart<List<ProjectEntity>, ProjectFailure> listProjects(ProjectFilter filter);
}
