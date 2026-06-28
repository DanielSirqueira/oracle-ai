import 'package:oracle_core/oracle_core.dart';

import '../../../domain/entities/handoff_entity.dart';
import '../../../domain/errors/handoff_failure.dart';
import '../../../infra/datasources/handoff_datasource.dart';
import '../../mappers/database/database_handoff_mapper.dart';

class DatabaseHandoffDatasource implements HandoffDatasource {
  final Database _database;
  const DatabaseHandoffDatasource({required Database database}) : _database = database;

  // jsonb columns cast to text so DataRowType.toStringList() can parse them.
  static const _columns =
      'id, project_id, source_session_id, from_agent, to_agent, summary, '
      'open_questions::text AS open_questions, next_steps::text AS next_steps, '
      'files_touched::text AS files_touched, status, cwd, created_at, accepted_at';

  @override
  Future<HandoffEntity> beginHandoff(HandoffEntity handoff) async {
    try {
      final result = await _database.executeUpdate(SqlStatement(
        'INSERT INTO handoffs (project_id, source_session_id, from_agent, to_agent, summary, '
        'open_questions, next_steps, files_touched, cwd) '
        'VALUES (:project_id::uuid, :source_session_id::uuid, :from_agent, :to_agent, :summary, '
        ':open_questions::jsonb, :next_steps::jsonb, :files_touched::jsonb, :cwd) '
        'RETURNING id, created_at',
        DatabaseHandoffMapper.toInsertParams(handoff),
      ));
      final row = result.rows.first;
      return handoff.copyWith(
        id: IdVO(row['id']!.toText()!),
        createdAt: row['created_at']?.toDateTime(),
      );
    } on DatabaseFailure catch (error) {
      throw DatasourceHandoffFailure(errorMessage: error.errorMessage, stackTrace: StackTrace.current);
    }
  }

  @override
  Future<List<HandoffEntity>> pendingHandoffs(IdVO projectId) async {
    try {
      final result = await _database.select(SqlStatement(
        "SELECT $_columns FROM handoffs "
        "WHERE project_id = :pid::uuid AND status = 'open' "
        'ORDER BY created_at DESC LIMIT 1',
        {'pid': projectId.value},
      ));
      return result.rows.map(DatabaseHandoffMapper.fromRow).toList();
    } on DatabaseFailure catch (error) {
      throw DatasourceHandoffFailure(errorMessage: error.errorMessage, stackTrace: StackTrace.current);
    }
  }

  @override
  Future<HandoffEntity> acceptHandoff(IdVO id) async {
    try {
      final result = await _database.executeUpdate(SqlStatement(
        "UPDATE handoffs SET status = 'accepted', accepted_at = NOW() "
        "WHERE id = :id::uuid AND status = 'open' "
        'RETURNING $_columns',
        {'id': id.value},
      ));
      if (result.rows.isEmpty) {
        throw HandoffNotFoundFailure(stackTrace: StackTrace.current);
      }
      return DatabaseHandoffMapper.fromRow(result.rows.first);
    } on DatabaseFailure catch (error) {
      throw DatasourceHandoffFailure(errorMessage: error.errorMessage, stackTrace: StackTrace.current);
    }
  }
}
