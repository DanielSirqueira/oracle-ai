import 'package:oracle_core/oracle_core.dart';

import '../../../domain/dtos/metric_delta.dart';
import '../../../domain/dtos/metrics_summary.dart';
import '../../../domain/entities/session_metric_entity.dart';
import '../../../domain/errors/metrics_failure.dart';
import '../../../infra/datasources/metrics_datasource.dart';

/// PostgreSQL-backed measurement harness. Deltas are ADDED via an upsert so
/// counts accumulate across the session as hook events arrive.
class DatabaseMetricsDatasource implements MetricsDatasource {
  final Database _database;
  const DatabaseMetricsDatasource({required Database database}) : _database = database;

  static const _columns =
      'id, project_id, external_id, label, input_tokens, output_tokens, '
      'cache_creation_tokens, cache_read_tokens, compactions, tool_uses, turns, updated_at';

  @override
  Future<SessionMetricEntity> addMetric(MetricDelta d) async {
    try {
      final result = await _database.executeUpdate(SqlStatement(
        'INSERT INTO session_metrics '
        '(project_id, external_id, label, input_tokens, output_tokens, '
        'cache_creation_tokens, cache_read_tokens, compactions, tool_uses, turns) '
        'VALUES (:pid::uuid, :ext, :label, :it, :ot, :cc, :cr, :comp, :tools, :turns) '
        'ON CONFLICT (project_id, external_id, label) DO UPDATE SET '
        'input_tokens = session_metrics.input_tokens + EXCLUDED.input_tokens, '
        'output_tokens = session_metrics.output_tokens + EXCLUDED.output_tokens, '
        'cache_creation_tokens = session_metrics.cache_creation_tokens + EXCLUDED.cache_creation_tokens, '
        'cache_read_tokens = session_metrics.cache_read_tokens + EXCLUDED.cache_read_tokens, '
        'compactions = session_metrics.compactions + EXCLUDED.compactions, '
        'tool_uses = session_metrics.tool_uses + EXCLUDED.tool_uses, '
        'turns = session_metrics.turns + EXCLUDED.turns, updated_at = now() '
        'RETURNING $_columns',
        {
          'pid': d.projectId.value,
          'ext': d.externalId,
          'label': d.label,
          'it': d.inputTokens,
          'ot': d.outputTokens,
          'cc': d.cacheCreationTokens,
          'cr': d.cacheReadTokens,
          'comp': d.compactions,
          'tools': d.toolUses,
          'turns': d.turns,
        },
      ));
      return _fromRow(result.rows.first);
    } on DatabaseFailure catch (error) {
      throw DatasourceMetricsFailure(errorMessage: error.errorMessage, stackTrace: StackTrace.current);
    }
  }

  @override
  Future<List<MetricsSummary>> summary({String? label}) async {
    try {
      final params = <String, Object?>{};
      var where = '';
      if (label != null && label.trim().isNotEmpty) {
        where = 'WHERE label = :label ';
        params['label'] = label.trim();
      }
      final result = await _database.select(SqlStatement(
        'SELECT label, count(*) AS sessions, '
        'sum(input_tokens) AS input_tokens, sum(output_tokens) AS output_tokens, '
        'sum(cache_creation_tokens) AS cache_creation_tokens, '
        'sum(cache_read_tokens) AS cache_read_tokens, '
        'sum(compactions) AS compactions, sum(turns) AS turns '
        'FROM session_metrics ${where}GROUP BY label ORDER BY label',
        params,
      ));
      return result.rows
          .map((r) => MetricsSummary(
                label: r['label']?.toText() ?? 'default',
                sessions: r['sessions']?.toInt() ?? 0,
                inputTokens: r['input_tokens']?.toInt() ?? 0,
                outputTokens: r['output_tokens']?.toInt() ?? 0,
                cacheCreationTokens: r['cache_creation_tokens']?.toInt() ?? 0,
                cacheReadTokens: r['cache_read_tokens']?.toInt() ?? 0,
                compactions: r['compactions']?.toInt() ?? 0,
                turns: r['turns']?.toInt() ?? 0,
              ))
          .toList();
    } on DatabaseFailure catch (error) {
      throw DatasourceMetricsFailure(errorMessage: error.errorMessage, stackTrace: StackTrace.current);
    }
  }

  @override
  Future<List<SessionMetricEntity>> recent(IdVO projectId, {int limit = 20}) async {
    try {
      final result = await _database.select(SqlStatement(
        'SELECT $_columns FROM session_metrics WHERE project_id = :pid::uuid '
        'ORDER BY updated_at DESC LIMIT :lim',
        {'pid': projectId.value, 'lim': limit},
      ));
      return result.rows.map(_fromRow).toList();
    } on DatabaseFailure catch (error) {
      throw DatasourceMetricsFailure(errorMessage: error.errorMessage, stackTrace: StackTrace.current);
    }
  }

  static SessionMetricEntity _fromRow(Map<String, DataRowType> row) => SessionMetricEntity(
        id: IdVO(row['id']!.toText()!),
        projectId: IdVO(row['project_id']!.toText()!),
        externalId: row['external_id']?.toText() ?? '',
        label: row['label']?.toText() ?? 'default',
        inputTokens: row['input_tokens']?.toInt() ?? 0,
        outputTokens: row['output_tokens']?.toInt() ?? 0,
        cacheCreationTokens: row['cache_creation_tokens']?.toInt() ?? 0,
        cacheReadTokens: row['cache_read_tokens']?.toInt() ?? 0,
        compactions: row['compactions']?.toInt() ?? 0,
        toolUses: row['tool_uses']?.toInt() ?? 0,
        turns: row['turns']?.toInt() ?? 0,
        updatedAt: row['updated_at']?.toDateTime(),
      );
}
