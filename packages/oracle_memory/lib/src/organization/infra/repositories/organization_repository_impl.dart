import 'package:oracle_core/oracle_core.dart';

import '../../domain/dtos/filters/organization_filter.dart';
import '../../domain/entities/organization_entity.dart';
import '../../domain/errors/organization_failure.dart';
import '../../domain/repositories/organization_repository.dart';
import '../datasources/organization_datasource.dart';

class OrganizationRepositoryImpl implements OrganizationRepository {
  final OrganizationDatasource _datasource;
  const OrganizationRepositoryImpl({required OrganizationDatasource datasource}) : _datasource = datasource;

  @override
  AsyncResultDart<OrganizationEntity, OrganizationFailure> registerOrganization(OrganizationEntity organization) async {
    try {
      return Success(await _datasource.registerOrganization(organization));
    } on OrganizationFailure catch (failure) {
      return Failure(failure);
    }
  }

  @override
  AsyncResultDart<OrganizationEntity, OrganizationFailure> getOrganizationById(IdVO id) async {
    try {
      return Success(await _datasource.getOrganizationById(id));
    } on OrganizationFailure catch (failure) {
      return Failure(failure);
    }
  }

  @override
  AsyncResultDart<List<OrganizationEntity>, OrganizationFailure> listOrganizations(OrganizationFilter filter) async {
    try {
      return Success(await _datasource.listOrganizations(filter));
    } on OrganizationFailure catch (failure) {
      return Failure(failure);
    }
  }
}
