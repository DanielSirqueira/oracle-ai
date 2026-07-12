import 'package:oracle_core/oracle_core.dart';

import '../entities/module_entity.dart';
import '../errors/module_failure.dart';
import '../repositories/module_repository.dart';

/// Fetches a module by id.
abstract interface class GetModuleByIdUsecase {
  AsyncResultDart<ModuleEntity, ModuleFailure> call(IdVO id);
}

class GetModuleByIdUsecaseImpl implements GetModuleByIdUsecase {
  final ModuleRepository _repository;
  const GetModuleByIdUsecaseImpl(this._repository);

  @override
  AsyncResultDart<ModuleEntity, ModuleFailure> call(IdVO id) => _repository.getModuleById(id);
}
