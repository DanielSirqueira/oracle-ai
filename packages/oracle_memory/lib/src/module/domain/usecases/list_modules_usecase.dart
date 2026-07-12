import 'package:oracle_core/oracle_core.dart';

import '../dtos/filters/module_filter.dart';
import '../entities/module_entity.dart';
import '../errors/module_failure.dart';
import '../repositories/module_repository.dart';

/// Lists a project's modules.
abstract interface class ListModulesUsecase {
  AsyncResultDart<List<ModuleEntity>, ModuleFailure> call(ModuleFilter filter);
}

class ListModulesUsecaseImpl implements ListModulesUsecase {
  final ModuleRepository _repository;
  const ListModulesUsecaseImpl(this._repository);

  @override
  AsyncResultDart<List<ModuleEntity>, ModuleFailure> call(ModuleFilter filter) =>
      _repository.listModules(filter);
}
