import 'package:oracle_core/oracle_core.dart';

import '../entities/organization_entity.dart';
import '../errors/organization_failure.dart';
import '../repositories/organization_repository.dart';

abstract interface class GetOrganizationByIdUsecase {
  AsyncResultDart<OrganizationEntity, OrganizationFailure> call(IdVO id);
}

class GetOrganizationByIdUsecaseImpl implements GetOrganizationByIdUsecase {
  final OrganizationRepository _repository;
  const GetOrganizationByIdUsecaseImpl(this._repository);

  @override
  AsyncResultDart<OrganizationEntity, OrganizationFailure> call(IdVO id) => _repository.getOrganizationById(id);
}
