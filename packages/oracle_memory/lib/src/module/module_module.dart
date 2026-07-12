import 'package:oracle_core/oracle_core.dart';

import 'domain/repositories/module_repository.dart';
import 'domain/usecases/get_module_by_id_usecase.dart';
import 'domain/usecases/list_modules_usecase.dart';
import 'domain/usecases/resolve_module_usecase.dart';
import 'external/datasources/database/database_module_datasource.dart';
import 'infra/datasources/module_datasource.dart';
import 'infra/repositories/module_repository_impl.dart';

/// DI bindings for the module feature (Datasource → Repository → UseCases).
class ModuleModule extends Module {
  @override
  void binds(AutoInjector i) {
    i
      ..addLazySingleton<ModuleDatasource>(DatabaseModuleDatasource.new)
      ..addLazySingleton<ModuleRepository>(ModuleRepositoryImpl.new)
      ..addLazySingleton<ResolveModuleUsecase>(ResolveModuleUsecaseImpl.new)
      ..addLazySingleton<GetModuleByIdUsecase>(GetModuleByIdUsecaseImpl.new)
      ..addLazySingleton<ListModulesUsecase>(ListModulesUsecaseImpl.new);
  }
}
