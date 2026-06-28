import 'package:oracle_core/oracle_core.dart';

import '../../../domain/dtos/decay_policy.dart';
import '../../../domain/dtos/lint_report.dart';
import '../../../domain/dtos/maintenance_report.dart';
import '../../../domain/errors/maintenance_failure.dart';
import '../../../infra/datasources/maintenance_datasource.dart';

/// PostgreSQL + pgvector backed maintenance sweep. Soft-forgets memories
/// (is_latest=false + retired_at + retired_reason) — reversible and audited.
class DatabaseMaintenanceDatasource implements MaintenanceDatasource {
  final Database _database;
  const DatabaseMaintenanceDatasource({required Database database}) : _database = database;

  /// Predicate shared by decay dry-run and apply: stale + low-value + cold,
  /// restricted to the eligible tiers. `COALESCE(last_accessed_at, created_at)`
  /// means a never-read memory ages from its creation.
  static const _decayWhere =
      'is_latest AND retired_at IS NULL '
      'AND tier = ANY(:tiers) '
      'AND importance < :minImp '
      'AND access_count < :minAcc '
      "AND COALESCE(last_accessed_at, created_at) < now() - (:staleDays * interval '1 day')";

  @override
  Future<List<MaintenanceItem>> decaySweep(DecayPolicy policy) async {
    try {
      final params = <String, Object?>{
        'tiers': policy.eligibleTiers,
        'minImp': policy.minImportance,
        'minAcc': policy.minAccessCount,
        'staleDays': policy.staleDays,
        'lim': policy.limit,
      };

      if (policy.dryRun) {
        final result = await _database.select(SqlStatement(
          'SELECT id, title FROM memories WHERE $_decayWhere LIMIT :lim',
          params,
        ));
        return _items(result);
      }

      final result = await _database.executeUpdate(SqlStatement(
        'WITH c AS (SELECT id FROM memories WHERE $_decayWhere LIMIT :lim) '
        'UPDATE memories m SET is_latest = false, retired_at = now(), '
        "retired_reason = 'auto-decay', updated_at = now() "
        'FROM c WHERE m.id = c.id RETURNING m.id, m.title',
        params,
      ));
      return _items(result);
    } on DatabaseFailure catch (error) {
      throw DatasourceMaintenanceFailure(
          errorMessage: error.errorMessage, stackTrace: StackTrace.current);
    }
  }

  @override
  Future<List<MaintenanceItem>> dedupSweep(DecayPolicy policy) async {
    try {
      final params = <String, Object?>{'dist': policy.dedupDistance, 'lim': policy.limit};

      // A memory is a dedup candidate when a STRICTLY stronger near-duplicate
      // exists in the same owner+kind. The total order (importance, created_at,
      // id) guarantees only the non-strongest of a tight cluster is retired.
      const candidate = 'SELECT m.id, m.title FROM memories m '
          'WHERE m.is_latest AND m.retired_at IS NULL AND m.embedding IS NOT NULL '
          'AND EXISTS (SELECT 1 FROM memories o '
          'WHERE o.is_latest AND o.retired_at IS NULL AND o.embedding IS NOT NULL '
          'AND o.id <> m.id AND o.kind = m.kind '
          'AND o.product_id IS NOT DISTINCT FROM m.product_id '
          'AND o.project_id IS NOT DISTINCT FROM m.project_id '
          'AND (o.embedding <=> m.embedding) < :dist '
          'AND (o.importance, o.created_at, o.id) > (m.importance, m.created_at, m.id)) '
          'LIMIT :lim';

      if (policy.dryRun) {
        final result = await _database.select(SqlStatement(candidate, params));
        return _items(result);
      }

      final result = await _database.executeUpdate(SqlStatement(
        'WITH d AS ($candidate) '
        'UPDATE memories m SET is_latest = false, retired_at = now(), '
        "retired_reason = 'auto-dedup', updated_at = now() "
        'FROM d WHERE m.id = d.id RETURNING m.id, m.title',
        params,
      ));
      return _items(result);
    } on DatabaseFailure catch (error) {
      throw DatasourceMaintenanceFailure(
          errorMessage: error.errorMessage, stackTrace: StackTrace.current);
    }
  }

  @override
  Future<LintReport> lint() async {
    try {
      final result = await _database.select(const SqlStatement(
        'SELECT '
        '(SELECT count(*) FROM memories WHERE is_latest AND embedding IS NULL) AS mem_no_emb, '
        '(SELECT count(*) FROM rules WHERE is_latest AND embedding IS NULL) AS rule_no_emb, '
        "(SELECT count(*) FROM requests r WHERE r.created_at < now() - interval '1 day' "
        'AND NOT EXISTS (SELECT 1 FROM messages m WHERE m.request_id = r.id)) AS empty_requests',
      ));
      final row = result.rows.first;
      return LintReport(
        memoriesWithoutEmbedding: row['mem_no_emb']?.toInt() ?? 0,
        rulesWithoutEmbedding: row['rule_no_emb']?.toInt() ?? 0,
        requestsWithoutMessages: row['empty_requests']?.toInt() ?? 0,
      );
    } on DatabaseFailure catch (error) {
      throw DatasourceMaintenanceFailure(
          errorMessage: error.errorMessage, stackTrace: StackTrace.current);
    }
  }

  static List<MaintenanceItem> _items(ResultDatabase result) => result.rows
      .map((row) => MaintenanceItem(
            id: row['id']?.toText() ?? '',
            title: row['title']?.toText() ?? '',
          ))
      .toList();
}
