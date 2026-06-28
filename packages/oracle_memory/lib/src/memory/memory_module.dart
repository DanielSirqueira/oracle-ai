import 'package:oracle_core/oracle_core.dart';

import 'domain/repositories/memory_repository.dart';
import 'domain/usecases/forget_memory_usecase.dart';
import 'domain/usecases/get_memory_by_id_usecase.dart';
import 'domain/usecases/relevant_memories_usecase.dart';
import 'domain/usecases/save_memory_usecase.dart';
import 'domain/usecases/search_memories_usecase.dart';
import 'domain/usecases/top_memories_usecase.dart';
import 'external/datasources/database/database_memory_datasource.dart';
import 'infra/datasources/memory_datasource.dart';
import 'infra/repositories/memory_repository_impl.dart';

/// DI bindings for the memory feature (Datasource → Repository → UseCases).
/// Requires a `Database` to be registered.
class MemoryModule extends Module {
  @override
  void binds(AutoInjector i) {
    i
      ..addLazySingleton<MemoryDatasource>(DatabaseMemoryDatasource.new)
      ..addLazySingleton<MemoryRepository>(MemoryRepositoryImpl.new)
      ..addLazySingleton<SaveMemoryUsecase>(SaveMemoryUsecaseImpl.new)
      ..addLazySingleton<GetMemoryByIdUsecase>(GetMemoryByIdUsecaseImpl.new)
      ..addLazySingleton<SearchMemoriesUsecase>(SearchMemoriesUsecaseImpl.new)
      ..addLazySingleton<TopMemoriesUsecase>(TopMemoriesUsecaseImpl.new)
      ..addLazySingleton<RelevantMemoriesUsecase>(RelevantMemoriesUsecaseImpl.new)
      ..addLazySingleton<ForgetMemoryUsecase>(ForgetMemoryUsecaseImpl.new);
  }
}
