import 'package:oracle_core/oracle_core.dart';

import 'domain/repositories/architecture_repository.dart';
import 'domain/usecases/get_architecture_by_area_usecase.dart';
import 'domain/usecases/retire_architecture_usecase.dart';
import 'domain/usecases/save_architecture_usecase.dart';
import 'domain/usecases/search_architecture_usecase.dart';
import 'external/datasources/database/database_architecture_datasource.dart';
import 'infra/datasources/architecture_datasource.dart';
import 'infra/repositories/architecture_repository_impl.dart';

class ArchitectureModule extends Module {
  @override
  void binds(AutoInjector i) {
    i
      ..addLazySingleton<ArchitectureDatasource>(DatabaseArchitectureDatasource.new)
      ..addLazySingleton<ArchitectureRepository>(ArchitectureRepositoryImpl.new)
      ..addLazySingleton<SaveArchitectureUsecase>(SaveArchitectureUsecaseImpl.new)
      ..addLazySingleton<GetArchitectureByAreaUsecase>(GetArchitectureByAreaUsecaseImpl.new)
      ..addLazySingleton<SearchArchitectureUsecase>(SearchArchitectureUsecaseImpl.new)
      ..addLazySingleton<RetireArchitectureUsecase>(RetireArchitectureUsecaseImpl.new);
  }
}
