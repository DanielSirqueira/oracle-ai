import 'package:oracle_core/oracle_core.dart';

import '../../../domain/dtos/filters/module_filter.dart';
import '../../../domain/entities/module_entity.dart';
import '../../../domain/errors/module_failure.dart';
import '../../../infra/datasources/module_datasource.dart';
import '../../mappers/database/database_module_mapper.dart';

/// PostgreSQL-backed [ModuleDatasource].
class DatabaseModuleDatasource implements ModuleDatasource {
  final Database _database;
  const DatabaseModuleDatasource({required Database database}) : _database = database;

  static const _columns = DatabaseModuleMapper.columns;

  @override
  Future<ModuleEntity> resolveModule(ModuleEntity module) async {
    try {
      // Race-safe get-or-create keyed on (project_id, path), targeting the
      // partial unique index uq_modules_project_path (WHERE path IS NOT NULL).
      final result = await _database.executeUpdate(SqlStatement(
        'INSERT INTO modules (project_id, key, name, path, description) '
        'VALUES (:project_id::uuid, :key, :name, :path, :description) '
        'ON CONFLICT (project_id, path) WHERE path IS NOT NULL '
        'DO UPDATE SET updated_at = now() '
        'RETURNING $_columns',
        DatabaseModuleMapper.toInsertParams(module),
      ));
      return DatabaseModuleMapper.fromRow(result.rows.first);
    } on DatabaseFailure catch (error) {
      throw DatasourceModuleFailure(errorMessage: error.errorMessage, stackTrace: StackTrace.current);
    }
  }

  @override
  Future<ModuleEntity> getModuleById(IdVO id) async {
    try {
      final result = await _database.select(SqlStatement(
        'SELECT $_columns FROM modules WHERE id = :id::uuid',
        {'id': id.value},
      ));
      if (result.rows.isEmpty) {
        throw ModuleNotFoundFailure(stackTrace: StackTrace.current);
      }
      return DatabaseModuleMapper.fromRow(result.rows.first);
    } on DatabaseFailure catch (error) {
      throw DatasourceModuleFailure(errorMessage: error.errorMessage, stackTrace: StackTrace.current);
    }
  }

  @override
  Future<List<ModuleEntity>> listModules(ModuleFilter filter) async {
    try {
      final params = <String, Object?>{
        'pid': filter.projectId.value,
        'limit': filter.limit,
        'offset': filter.offset,
      };
      var where = 'WHERE project_id = :pid::uuid';
      if (filter.search.trim().isNotEmpty) {
        where += ' AND (name ILIKE :like OR key ILIKE :like OR path ILIKE :like)';
        params['like'] = '%${filter.search.trim()}%';
      }
      final result = await _database.select(SqlStatement(
        'SELECT $_columns FROM modules $where ORDER BY name LIMIT :limit OFFSET :offset',
        params,
      ));
      return result.rows.map(DatabaseModuleMapper.fromRow).toList();
    } on DatabaseFailure catch (error) {
      throw DatasourceModuleFailure(errorMessage: error.errorMessage, stackTrace: StackTrace.current);
    }
  }
}
