import 'package:oracle_core/oracle_core.dart';

import '../../domain/dtos/filters/module_filter.dart';
import '../../domain/entities/module_entity.dart';
import '../../domain/errors/module_failure.dart';
import '../../domain/repositories/module_repository.dart';
import '../datasources/module_datasource.dart';

class ModuleRepositoryImpl implements ModuleRepository {
  final ModuleDatasource _datasource;
  const ModuleRepositoryImpl({required ModuleDatasource datasource}) : _datasource = datasource;

  @override
  AsyncResultDart<ModuleEntity, ModuleFailure> resolveModule(ModuleEntity module) async {
    try {
      return Success(await _datasource.resolveModule(module));
    } on ModuleFailure catch (failure) {
      return Failure(failure);
    }
  }

  @override
  AsyncResultDart<ModuleEntity, ModuleFailure> getModuleById(IdVO id) async {
    try {
      return Success(await _datasource.getModuleById(id));
    } on ModuleFailure catch (failure) {
      return Failure(failure);
    }
  }

  @override
  AsyncResultDart<List<ModuleEntity>, ModuleFailure> listModules(ModuleFilter filter) async {
    try {
      return Success(await _datasource.listModules(filter));
    } on ModuleFailure catch (failure) {
      return Failure(failure);
    }
  }
}
