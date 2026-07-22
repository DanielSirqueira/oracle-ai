import 'dart:convert';

import 'package:oracle_core/oracle_core.dart';

import '../../../domain/entities/agent_search_entity.dart';
import '../../../domain/errors/agent_search_failure.dart';
import '../../../infra/datasources/agent_search_datasource.dart';

/// PostgreSQL-backed agent search history.
class DatabaseAgentSearchDatasource implements AgentSearchDatasource {
  final Database _database;
  const DatabaseAgentSearchDatasource({required Database database})
    : _database = database;

  static const _columns =
      'id, session_id, request_id, tool, query, scope::text AS scope, filters::text AS filters, '
      'results::text AS results, hits, latency_ms, created_at';

  @override
  Future<void> logSearch(AgentSearchEntity s) async {
    try {
      await _database.executeUpdate(
        SqlStatement(
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
        ),
      );
    } on DatabaseFailure catch (e) {
      throw DatasourceAgentSearchFailure(
        errorMessage: e.errorMessage,
        stackTrace: StackTrace.current,
      );
    }
  }

  @override
  Future<List<AgentSearchEntity>> recentSearches(
    IdVO projectId, {
    int limit = 100,
  }) async {
    try {
      final result = await _database.select(
        SqlStatement(
          'SELECT $_columns FROM agent_searches '
          "WHERE scope->>'projectId' = :pid "
          'ORDER BY created_at DESC LIMIT :limit',
          {'pid': projectId.value, 'limit': limit},
        ),
      );
      return _hydrateResults(result.rows.map(_fromRow).toList());
    } on DatabaseFailure catch (e) {
      throw DatasourceAgentSearchFailure(
        errorMessage: e.errorMessage,
        stackTrace: StackTrace.current,
      );
    }
  }

  /// Old search logs only stored ids + scores. Resolve them in four bounded
  /// batch queries so the audit UI can show the actual record without causing
  /// an N+1 query storm. New logs already contain snapshots and are left intact.
  Future<List<AgentSearchEntity>> _hydrateResults(
    List<AgentSearchEntity> searches,
  ) async {
    final idsByType = <String, Set<String>>{
      'memory': {},
      'rule': {},
      'skill': {},
      'architecture': {},
    };
    final uuid = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
    );
    for (final search in searches) {
      final type = search.tool == 'rules_for_task' ? 'rule' : search.tool;
      final target = idsByType[type];
      if (target == null) continue;
      for (final item in search.results) {
        if (item['title'] != null || item['name'] != null) continue;
        final id = '${item['id'] ?? ''}';
        if (uuid.hasMatch(id)) target.add(id);
      }
    }

    final records = <String, Map<String, dynamic>>{};
    Future<void> load(
      String type,
      String table,
      String projection,
      Map<String, dynamic> Function(Map<String, DataRowType>) map,
    ) async {
      final ids = idsByType[type]!;
      if (ids.isEmpty) return;
      final rows = await _database.select(
        SqlStatement(
          'SELECT id::text AS id, $projection FROM $table '
          'WHERE id IN (SELECT value::uuid FROM jsonb_array_elements_text(:ids::jsonb))',
          {'ids': jsonEncode(ids.toList())},
        ),
      );
      for (final row in rows.rows) {
        final id = row['id']?.toText();
        if (id != null) records['$type:$id'] = map(row);
      }
    }

    await load(
      'memory',
      'memories',
      'title, body, kind, tier',
      (r) => {
        'title': r['title']?.toText() ?? '',
        'subtitle':
            '${r['kind']?.toText() ?? ''} · ${r['tier']?.toText() ?? ''}',
        'content': r['body']?.toText() ?? '',
      },
    );
    await load(
      'rule',
      'rules',
      'title, content, key, scope, severity',
      (r) => {
        'title': r['title']?.toText() ?? '',
        'subtitle':
            '${r['key']?.toText() ?? ''} · ${r['scope']?.toText() ?? ''} · ${r['severity']?.toText() ?? ''}',
        'content': r['content']?.toText() ?? '',
      },
    );
    await load(
      'skill',
      'skills',
      'name, description, content, key',
      (r) => {
        'title': r['name']?.toText() ?? '',
        'subtitle':
            '${r['key']?.toText() ?? ''} · ${r['description']?.toText() ?? ''}',
        'content': r['content']?.toText() ?? '',
      },
    );
    await load(
      'architecture',
      'architectures',
      'area, content',
      (r) => {
        'title': r['area']?.toText() ?? '',
        'subtitle': 'architecture',
        'content': r['content']?.toText() ?? '',
      },
    );

    return [
      for (final search in searches)
        search.copyWith(
          results: [
            for (final item in search.results)
              () {
                if (item['title'] != null || item['name'] != null) return item;
                final type = search.tool == 'rules_for_task'
                    ? 'rule'
                    : search.tool;
                final record = records['$type:${item['id']}'];
                return record == null ? item : {...item, ...record};
              }(),
          ],
        ),
    ];
  }

  static AgentSearchEntity _fromRow(Map<String, DataRowType> row) {
    Map<String, dynamic> obj(String? s) => (s == null || s.isEmpty)
        ? const {}
        : jsonDecode(s) as Map<String, dynamic>;
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
