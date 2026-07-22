import 'package:oracle_core/oracle_core.dart';

import '../errors/project_failure.dart';
import '../repositories/project_repository.dart';

/// Deletes a project and EVERYTHING scoped to it (memories, rules, sessions,
/// flows, runs… — every table cascades on project_id). Built for cleaning up
/// wrongly auto-registered projects (e.g. a worktree or temp dir that resolved
/// as a new project before the canonicalization fix).
abstract interface class DeleteProjectUsecase {
  AsyncResultDart<Unit, ProjectFailure> call(IdVO id);
}

class DeleteProjectUsecaseImpl implements DeleteProjectUsecase {
  final ProjectRepository _repository;
  const DeleteProjectUsecaseImpl(this._repository);

  @override
  AsyncResultDart<Unit, ProjectFailure> call(IdVO id) =>
      _repository.deleteProject(id);
}
