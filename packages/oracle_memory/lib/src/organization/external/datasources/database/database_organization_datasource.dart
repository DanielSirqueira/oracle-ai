import 'package:oracle_core/oracle_core.dart';

import '../../../domain/dtos/filters/organization_filter.dart';
import '../../../domain/entities/organization_entity.dart';
import '../../../domain/errors/organization_failure.dart';
import '../../../infra/datasources/organization_datasource.dart';
import '../../mappers/database/database_organization_mapper.dart';

class DatabaseOrganizationDatasource implements OrganizationDatasource {
  final Database _database;
  const DatabaseOrganizationDatasource({required Database database}) : _database = database;

  static const _columns = 'id, name, description, created_at, updated_at';

  @override
  Future<OrganizationEntity> registerOrganization(OrganizationEntity organization) async {
    try {
      final params = DatabaseOrganizationMapper.toInsertParams(organization);
      // Resolve-or-create: organizations have no natural key, so a second
      // oracle_organization_register with the same name would fork the ecosystem into
      // two owners and split all downstream scoping. Reuse the existing organization
      // with the same (case-insensitive) name instead of inserting a duplicate.
      final existing = await _database.select(SqlStatement(
        'SELECT $_columns FROM organizations WHERE lower(name) = lower(:name) '
        'ORDER BY created_at LIMIT 1',
        {'name': params['name']},
      ));
      if (existing.rows.isNotEmpty) {
        return DatabaseOrganizationMapper.fromRow(existing.rows.first);
      }
      final result = await _database.executeUpdate(SqlStatement(
        'INSERT INTO organizations (name, description) VALUES (:name, :description) '
        'RETURNING id, created_at, updated_at',
        params,
      ));
      final row = result.rows.first;
      return organization.copyWith(
        id: IdVO(row['id']!.toText()!),
        createdAt: row['created_at']?.toDateTime(),
        updatedAt: row['updated_at']?.toDateTime(),
      );
    } on DatabaseFailure catch (error) {
      throw DatasourceOrganizationFailure(errorMessage: error.errorMessage, stackTrace: StackTrace.current);
    }
  }

  @override
  Future<OrganizationEntity> getOrganizationById(IdVO id) async {
    try {
      final result = await _database.select(SqlStatement(
        'SELECT $_columns FROM organizations WHERE id = :id::uuid',
        {'id': id.value},
      ));
      if (result.rows.isEmpty) {
        throw OrganizationNotFoundFailure(stackTrace: StackTrace.current);
      }
      return DatabaseOrganizationMapper.fromRow(result.rows.first);
    } on DatabaseFailure catch (error) {
      throw DatasourceOrganizationFailure(errorMessage: error.errorMessage, stackTrace: StackTrace.current);
    }
  }

  @override
  Future<List<OrganizationEntity>> listOrganizations(OrganizationFilter filter) async {
    try {
      final params = <String, Object?>{'limit': filter.limit, 'offset': filter.offset};
      var where = '';
      if (filter.search.trim().isNotEmpty) {
        where = 'WHERE name ILIKE :like';
        params['like'] = '%${filter.search.trim()}%';
      }
      final result = await _database.select(SqlStatement(
        'SELECT $_columns FROM organizations $where ORDER BY name LIMIT :limit OFFSET :offset',
        params,
      ));
      return result.rows.map(DatabaseOrganizationMapper.fromRow).toList();
    } on DatabaseFailure catch (error) {
      throw DatasourceOrganizationFailure(errorMessage: error.errorMessage, stackTrace: StackTrace.current);
    }
  }
}
