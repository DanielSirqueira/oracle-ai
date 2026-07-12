import 'package:oracle_core/oracle_core.dart';

import '../../domain/dtos/filters/module_filter.dart';
import '../../domain/entities/module_entity.dart';

/// Data-access contract for modules. Implementations **throw** typed failures;
/// the repository converts them into a `ResultDart`.
abstract interface class ModuleDatasource {
  /// Get-or-create a module by (project_id, path) — race-safe upsert.
  Future<ModuleEntity> resolveModule(ModuleEntity module);

  Future<ModuleEntity> getModuleById(IdVO id);

  Future<List<ModuleEntity>> listModules(ModuleFilter filter);
}
