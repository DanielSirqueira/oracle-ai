import 'package:oracle_core/oracle_core.dart';

import '../dtos/filters/organization_filter.dart';
import '../entities/organization_entity.dart';
import '../errors/organization_failure.dart';

abstract interface class OrganizationRepository {
  AsyncResultDart<OrganizationEntity, OrganizationFailure> registerOrganization(OrganizationEntity organization);

  AsyncResultDart<OrganizationEntity, OrganizationFailure> getOrganizationById(IdVO id);

  AsyncResultDart<List<OrganizationEntity>, OrganizationFailure> listOrganizations(OrganizationFilter filter);
}
