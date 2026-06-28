import 'package:oracle_core/oracle_core.dart';

import '../entities/project_entity.dart';
import '../errors/project_failure.dart';
import '../repositories/project_repository.dart';

/// Maps an agent's working directory ([repoPath], i.e. cwd) to a stable project,
/// creating it on first sight. This is how Claude Code / Codex obtain a
/// `projectId` without the user pre-registering anything.
abstract interface class ResolveProjectUsecase {
  AsyncResultDart<ProjectEntity, ProjectFailure> call(
    String repoPath, {
    String? name,
    IdVO? productId,
  });
}

class ResolveProjectUsecaseImpl implements ResolveProjectUsecase {
  final ProjectRepository _repository;
  const ResolveProjectUsecaseImpl(this._repository);

  @override
  AsyncResultDart<ProjectEntity, ProjectFailure> call(
    String repoPath, {
    String? name,
    IdVO? productId,
  }) async {
    final normalized = _normalize(repoPath);
    if (normalized.isEmpty) {
      return Failure(ValidatedFieldProjectFailure(
        errorMessage: 'repoPath is required to resolve a project',
        stackTrace: StackTrace.current,
        fields: const [FieldSystemFailure(field: 'repoPath', message: 'Required')],
      ));
    }
    final projectName =
        (name != null && name.trim().isNotEmpty) ? name.trim() : _basename(normalized);
    return _repository.resolveProject(ProjectEntity(
      id: const IdVO.empty(),
      productId: productId,
      name: TextVO(projectName),
      repoPath: normalized,
    ));
  }

  /// Canonicalize a path so the same directory always maps to one project:
  /// unify separators and drop a trailing slash. (Casing is left as-is — agents
  /// on one machine report a consistent path.)
  static String _normalize(String path) {
    var p = path.trim().replaceAll(r'\', '/');
    while (p.length > 1 && p.endsWith('/')) {
      p = p.substring(0, p.length - 1);
    }
    return p;
  }

  static String _basename(String normalizedPath) {
    final segments = normalizedPath.split('/').where((s) => s.isNotEmpty).toList();
    return segments.isEmpty ? 'project' : segments.last;
  }
}
