import 'package:oracle_core/oracle_core.dart';

import '../entities/organization_entity.dart';
import '../errors/organization_failure.dart';
import '../repositories/organization_repository.dart';

abstract interface class RegisterOrganizationUsecase {
  AsyncResultDart<OrganizationEntity, OrganizationFailure> call(OrganizationEntity organization);
}

class RegisterOrganizationUsecaseImpl implements RegisterOrganizationUsecase {
  final OrganizationRepository _repository;
  const RegisterOrganizationUsecaseImpl(this._repository);

  @override
  AsyncResultDart<OrganizationEntity, OrganizationFailure> call(OrganizationEntity organization) async {
    if (organization.name.isBlank) {
      return Failure(ValidatedFieldOrganizationFailure(
        errorMessage: 'Organization name is required',
        stackTrace: StackTrace.current,
        fields: const [FieldSystemFailure(field: 'name', message: 'Required')],
      ));
    }
    return _repository.registerOrganization(organization);
  }
}
