import 'dart:convert';

import 'package:oracle_core/oracle_core.dart';

import '../../../domain/entities/agent_search_entity.dart';
import '../../../domain/errors/agent_search_failure.dart';
import '../../../infra/datasources/agent_search_datasource.dart';

/// PostgreSQL-backed agent search history.
class DatabaseAgentSearchDatasource implements AgentSearchDatasource {
  final Database _database;
  const DatabaseAgentSearchDatasource({required Database database}) : _database = database;

  static const _columns =
      'id, session_id, request_id, tool, query, scope::text AS scope, filters::text AS filters, '
      'results::text AS results, hits, latency_ms, created_at';

  @override
  Future<void> logSearch(AgentSearchEntity s) async {
    try {
      await _database.executeUpdate(SqlStatement(
        'INSERT INTO agent_searches '
        '(session_id, request_id, tool, query, scope, filters, results, hits, latency_ms) '
        'VALUES (:session_id::uuid, :request_id::uuid, :tool, :query, :scope::jsonb, '
        ':filters::jsonb, :results::jsonb, :hits, :latency_ms)',
        {
          'session_id': s.sessionId?.value,
          'request_id': s.requestId?.value,
          'tool': s.tool,
          'query': s.query,
          'scope': jsonEncode(s.scope),
          'filters': jsonEncode(s.filters),
          'results': jsonEncode(s.results),
          'hits': s.hits,
          'latency_ms': s.latencyMs,
        },
      ));
    } on DatabaseFailure catch (e) {
      throw DatasourceAgentSearchFailure(errorMessage: e.errorMessage, stackTrace: StackTrace.current);
    }
  }

  @override
  Future<List<AgentSearchEntity>> recentSearches(IdVO projectId, {int limit = 100}) async {
    try {
      final result = await _database.select(SqlStatement(
        'SELECT $_columns FROM agent_searches '
        "WHERE scope->>'projectId' = :pid "
        'ORDER BY created_at DESC LIMIT :limit',
        {'pid': projectId.value, 'limit': limit},
      ));
      return result.rows.map(_fromRow).toList();
    } on DatabaseFailure catch (e) {
      throw DatasourceAgentSearchFailure(errorMessage: e.errorMessage, stackTrace: StackTrace.current);
    }
  }

  static AgentSearchEntity _fromRow(Map<String, DataRowType> row) {
    Map<String, dynamic> obj(String? s) =>
        (s == null || s.isEmpty) ? const {} : jsonDecode(s) as Map<String, dynamic>;
    List<Map<String, dynamic>> arr(String? s) => (s == null || s.isEmpty)
        ? const []
        : (jsonDecode(s) as List).cast<Map<String, dynamic>>();
    final sessionId = row['session_id']?.toText();
    final requestId = row['request_id']?.toText();
    return AgentSearchEntity(
      id: IdVO(row['id']!.toText()!),
      sessionId: sessionId == null ? null : IdVO(sessionId),
      requestId: requestId == null ? null : IdVO(requestId),
      tool: row['tool']!.toText() ?? '',
      query: row['query']!.toText() ?? '',
      scope: obj(row['scope']?.toText()),
      filters: obj(row['filters']?.toText()),
      results: arr(row['results']?.toText()),
      hits: row['hits']?.toInt() ?? 0,
      latencyMs: row['latency_ms']?.toInt(),
      createdAt: row['created_at']?.toDateTime(),
    );
  }
}
