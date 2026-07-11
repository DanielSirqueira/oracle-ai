import 'package:oracle_core/oracle_core.dart';

import 'domain/repositories/organization_repository.dart';
import 'domain/usecases/get_organization_by_id_usecase.dart';
import 'domain/usecases/list_organizations_usecase.dart';
import 'domain/usecases/register_organization_usecase.dart';
import 'external/datasources/database/database_organization_datasource.dart';
import 'infra/datasources/organization_datasource.dart';
import 'infra/repositories/organization_repository_impl.dart';

class OrganizationModule extends Module {
  @override
  void binds(AutoInjector i) {
    i
      ..addLazySingleton<OrganizationDatasource>(DatabaseOrganizationDatasource.new)
      ..addLazySingleton<OrganizationRepository>(OrganizationRepositoryImpl.new)
      ..addLazySingleton<RegisterOrganizationUsecase>(RegisterOrganizationUsecaseImpl.new)
      ..addLazySingleton<GetOrganizationByIdUsecase>(GetOrganizationByIdUsecaseImpl.new)
      ..addLazySingleton<ListOrganizationsUsecase>(ListOrganizationsUsecaseImpl.new);
  }
}
