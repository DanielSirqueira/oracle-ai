import 'package:oracle_core/oracle_core.dart';

import '../dtos/filters/module_filter.dart';
import '../entities/module_entity.dart';
import '../errors/module_failure.dart';

/// Business contract for module persistence.
abstract interface class ModuleRepository {
  /// Get-or-create a module by its (project, path) — the agent's working subpath.
  AsyncResultDart<ModuleEntity, ModuleFailure> resolveModule(ModuleEntity module);

  AsyncResultDart<ModuleEntity, ModuleFailure> getModuleById(IdVO id);

  AsyncResultDart<List<ModuleEntity>, ModuleFailure> listModules(ModuleFilter filter);
}
