import 'package:oracle_core/oracle_core.dart';

import '../dtos/filters/organization_filter.dart';
import '../entities/organization_entity.dart';
import '../errors/organization_failure.dart';
import '../repositories/organization_repository.dart';

abstract interface class ListOrganizationsUsecase {
  AsyncResultDart<List<OrganizationEntity>, OrganizationFailure> call(OrganizationFilter filter);
}

class ListOrganizationsUsecaseImpl implements ListOrganizationsUsecase {
  final OrganizationRepository _repository;
  const ListOrganizationsUsecaseImpl(this._repository);

  @override
  AsyncResultDart<List<OrganizationEntity>, OrganizationFailure> call(OrganizationFilter filter) =>
      _repository.listOrganizations(filter);
}
