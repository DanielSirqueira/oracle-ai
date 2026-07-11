import 'package:oracle_core/oracle_core.dart';

import '../../../domain/dtos/filters/project_filter.dart';
import '../../../domain/entities/project_entity.dart';
import '../../../domain/errors/project_failure.dart';
import '../../../infra/datasources/project_datasource.dart';
import '../../mappers/database/database_project_mapper.dart';

/// PostgreSQL-backed [ProjectDatasource]. All SQL is parameterized via
/// [SqlStatement]; `DatabaseFailure`s are translated into typed project failures.
class DatabaseProjectDatasource implements ProjectDatasource {
  final Database _database;
  const DatabaseProjectDatasource({required Database database}) : _database = database;

  @override
  Future<ProjectEntity> registerProject(ProjectEntity project) async {
    try {
      final result = await _database.executeUpdate(SqlStatement(
        'INSERT INTO projects (organization_id, name, description, repo_path) '
        'VALUES (:organization_id::uuid, :name, :description, :repo_path) '
        'RETURNING id, created_at, updated_at',
        DatabaseProjectMapper.toInsertParams(project),
      ));
      final row = result.rows.first;
      return project.copyWith(
        id: IdVO(row['id']!.toText()!),
        createdAt: row['created_at']?.toDateTime(),
        updatedAt: row['updated_at']?.toDateTime(),
      );
    } on DatabaseFailure catch (error) {
      throw DatasourceProjectFailure(
        errorMessage: error.errorMessage,
        stackTrace: StackTrace.current,
      );
    }
  }

  @override
  Future<ProjectEntity> resolveProject(ProjectEntity project) async {
    try {
      // Race-safe get-or-create keyed on repo_path. DO UPDATE (not DO NOTHING)
      // so RETURNING always yields the row — existing or freshly inserted.
      final result = await _database.executeUpdate(SqlStatement(
        'INSERT INTO projects (organization_id, name, description, repo_path) '
        'VALUES (:organization_id::uuid, :name, :description, :repo_path) '
        'ON CONFLICT (repo_path) DO UPDATE SET updated_at = now() '
        'RETURNING id, organization_id, name, description, repo_path, created_at, updated_at',
        DatabaseProjectMapper.toInsertParams(project),
      ));
      return DatabaseProjectMapper.fromRow(result.rows.first);
    } on DatabaseFailure catch (error) {
      throw DatasourceProjectFailure(
        errorMessage: error.errorMessage,
        stackTrace: StackTrace.current,
      );
    }
  }

  @override
  Future<ProjectEntity> getProjectById(IdVO id) async {
    try {
      final result = await _database.select(SqlStatement(
        'SELECT id, organization_id, name, description, repo_path, created_at, updated_at '
        'FROM projects WHERE id = :id::uuid',
        {'id': id.value},
      ));
      if (result.rows.isEmpty) {
        throw ProjectNotFoundFailure(stackTrace: StackTrace.current);
      }
      return DatabaseProjectMapper.fromRow(result.rows.first);
    } on DatabaseFailure catch (error) {
      throw DatasourceProjectFailure(
        errorMessage: error.errorMessage,
        stackTrace: StackTrace.current,
      );
    }
  }

  @override
  Future<List<ProjectEntity>> listProjects(ProjectFilter filter) async {
    try {
      final params = <String, Object?>{'limit': filter.limit, 'offset': filter.offset};
      final where = <String>[];
      if (filter.search.trim().isNotEmpty) {
        where.add('name ILIKE :like');
        params['like'] = '%${filter.search.trim()}%';
      }
      if (filter.organizationId != null) {
        where.add('organization_id = :organization_id::uuid');
        params['organization_id'] = filter.organizationId!.value;
      }
      final whereClause = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';
      final result = await _database.select(SqlStatement(
        'SELECT id, organization_id, name, description, repo_path, created_at, updated_at '
        'FROM projects $whereClause ORDER BY name LIMIT :limit OFFSET :offset',
        params,
      ));
      return result.rows.map(DatabaseProjectMapper.fromRow).toList();
    } on DatabaseFailure catch (error) {
      throw DatasourceProjectFailure(
        errorMessage: error.errorMessage,
        stackTrace: StackTrace.current,
      );
    }
  }
}
