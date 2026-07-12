import 'package:oracle_core/oracle_core.dart';

import '../entities/module_entity.dart';
import '../errors/module_failure.dart';
import '../repositories/module_repository.dart';

/// Maps an agent's working subpath (under the project's repo root) to a stable
/// module, creating it on first sight — so a module is DETECTED, not invented as
/// a fake project. Resolve-or-create keyed on (projectId, normalized path).
abstract interface class ResolveModuleUsecase {
  AsyncResultDart<ModuleEntity, ModuleFailure> call(
    IdVO projectId,
    String path, {
    String? name,
    String? description,
  });
}

class ResolveModuleUsecaseImpl implements ResolveModuleUsecase {
  final ModuleRepository _repository;
  const ResolveModuleUsecaseImpl(this._repository);

  @override
  AsyncResultDart<ModuleEntity, ModuleFailure> call(
    IdVO projectId,
    String path, {
    String? name,
    String? description,
  }) async {
    final normalized = _normalize(path);
    if (normalized.isEmpty) {
      return Failure(ValidatedFieldModuleFailure(
        errorMessage: 'A module path is required (the subpath under the repo root). '
            'Empty path means project-level — do not create a module.',
        stackTrace: StackTrace.current,
        fields: const [FieldSystemFailure(field: 'path', message: 'Required')],
      ));
    }
    final moduleName =
        (name != null && name.trim().isNotEmpty) ? name.trim() : _lastSegment(normalized);
    return _repository.resolveModule(ModuleEntity(
      id: const IdVO.empty(),
      projectId: projectId,
      key: _slug(normalized),
      name: TextVO(moduleName),
      path: normalized,
      description:
          (description != null && description.trim().isNotEmpty) ? TextVO(description.trim()) : null,
    ));
  }

  /// Canonicalize a subpath: unify separators, drop leading/trailing slashes, so
  /// `\services\auth\` and `services/auth` map to one module.
  static String _normalize(String path) {
    var p = path.trim().replaceAll(r'\', '/');
    while (p.startsWith('/')) {
      p = p.substring(1);
    }
    while (p.length > 1 && p.endsWith('/')) {
      p = p.substring(0, p.length - 1);
    }
    return p;
  }

  static String _lastSegment(String normalizedPath) {
    final segments = normalizedPath.split('/').where((s) => s.isNotEmpty).toList();
    return segments.isEmpty ? 'module' : segments.last;
  }

  /// Stable kebab-case slug of the full subpath (so nested modules stay distinct).
  static String _slug(String normalizedPath) {
    final s = normalizedPath
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return s.isEmpty ? 'module' : s;
  }
}
