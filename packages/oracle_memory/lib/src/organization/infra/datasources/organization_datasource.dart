import 'package:oracle_core/oracle_core.dart';

import '../../domain/dtos/filters/organization_filter.dart';
import '../../domain/entities/organization_entity.dart';

abstract interface class OrganizationDatasource {
  Future<OrganizationEntity> registerOrganization(OrganizationEntity organization);

  Future<OrganizationEntity> getOrganizationById(IdVO id);

  Future<List<OrganizationEntity>> listOrganizations(OrganizationFilter filter);
}
