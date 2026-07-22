import 'package:oracle_core/oracle_core.dart';

import 'domain/repositories/project_repository.dart';
import 'domain/usecases/delete_project_usecase.dart';
import 'domain/usecases/get_project_by_id_usecase.dart';
import 'domain/usecases/list_projects_usecase.dart';
import 'domain/usecases/register_project_usecase.dart';
import 'domain/usecases/resolve_project_usecase.dart';
import 'external/datasources/database/database_project_datasource.dart';
import 'infra/datasources/project_datasource.dart';
import 'infra/repositories/project_repository_impl.dart';

/// DI bindings for the project feature, in the canonical order
/// Datasource → Repository → UseCases. Requires a `Database` to be registered.
class ProjectModule extends Module {
  @override
  void binds(AutoInjector i) {
    i
      ..addLazySingleton<ProjectDatasource>(DatabaseProjectDatasource.new)
      ..addLazySingleton<ProjectRepository>(ProjectRepositoryImpl.new)
      ..addLazySingleton<RegisterProjectUsecase>(RegisterProjectUsecaseImpl.new)
      ..addLazySingleton<ResolveProjectUsecase>(ResolveProjectUsecaseImpl.new)
      ..addLazySingleton<GetProjectByIdUsecase>(GetProjectByIdUsecaseImpl.new)
      ..addLazySingleton<ListProjectsUsecase>(ListProjectsUsecaseImpl.new)
      ..addLazySingleton<DeleteProjectUsecase>(DeleteProjectUsecaseImpl.new);
  }
}
