import 'package:oracle_core/oracle_core.dart';

import '../../../domain/dtos/filters/rule_search_filter.dart';
import '../../../domain/dtos/rule_neighbor.dart';
import '../../../domain/dtos/rule_search_result.dart';
import '../../../domain/dtos/rules_for_task_query.dart';
import '../../../domain/entities/rule_entity.dart';
import '../../../domain/errors/rule_failure.dart';
import '../../../infra/datasources/rule_datasource.dart';
import '../../mappers/database/database_rule_mapper.dart';

/// PostgreSQL + pgvector backed [RuleDatasource].
///
/// - [saveRule]: supersedes the current latest rule with the same key in the
///   same owner (one transaction), then inserts the new version.
/// - [rulesForTask]: resolves product→project inheritance and override
///   (project rules win over product rules with the same key).
/// - [searchRules]: hybrid search (vector + full-text, RRF), like memory.
class DatabaseRuleDatasource implements RuleDatasource {
  final Database _database;
  const DatabaseRuleDatasource({required Database database}) : _database = database;

  // `embedding::text` so DataRowType.toVector() can parse it (driver returns
  // the vector type as binary).
  static const _columns =
      'id, product_id, project_id, key, scope, title, content, severity, priority, tags, '
      'embedding::text AS embedding, embedding_model, is_latest, supersedes, created_at, updated_at';

  static const _columnsM =
      'm.id, m.product_id, m.project_id, m.key, m.scope, m.title, m.content, m.severity, '
      'm.priority, m.tags, m.embedding::text AS embedding, m.embedding_model, m.is_latest, '
      'm.supersedes, m.created_at, m.updated_at';

  static const _rrfK = 60;
  static const _candidatePool = 50;

  @override
  Future<RuleEntity> saveRule(RuleEntity rule) async {
    try {
      // 1) Supersede the current latest rule with the same key in the same owner.
      final String supersedeSql;
      final Map<String, Object?> supersedeParams;
      if (rule.projectId != null) {
        supersedeSql = 'UPDATE rules SET is_latest = false '
            'WHERE is_latest AND key = :key AND project_id = :pid::uuid';
        supersedeParams = {'key': rule.key, 'pid': rule.projectId!.value};
      } else {
        supersedeSql = 'UPDATE rules SET is_latest = false '
            'WHERE is_latest AND key = :key AND project_id IS NULL AND product_id = :prodid::uuid';
        supersedeParams = {'key': rule.key, 'prodid': rule.productId!.value};
      }

      // 2) Insert the new version.
      const insertSql =
          'INSERT INTO rules (product_id, project_id, key, scope, title, content, '
          'severity, priority, tags, embedding, embedding_model, supersedes) '
          'VALUES (:product_id::uuid, :project_id::uuid, :key, :scope, :title, :content, '
          ':severity, :priority, :tags, :embedding::vector(1024), :embedding_model, :supersedes::uuid) '
          'RETURNING id, created_at, updated_at';

      final results = await _database.executeSavePoint([
        SavePointQuery(statement: SqlStatement(supersedeSql, supersedeParams)),
        SavePointQuery(statement: SqlStatement(insertSql, DatabaseRuleMapper.toInsertParams(rule))),
      ]);
      final row = results.last.rows.first;
      return rule.copyWith(
        id: IdVO(row['id']!.toText()!),
        createdAt: row['created_at']?.toDateTime(),
        updatedAt: row['updated_at']?.toDateTime(),
      );
    } on DatabaseFailure catch (error) {
      throw DatasourceRuleFailure(errorMessage: error.errorMessage, stackTrace: StackTrace.current);
    }
  }

  @override
  Future<RuleEntity?> currentByKey({IdVO? productId, IdVO? projectId, required String key}) async {
    try {
      final String sql;
      final Map<String, Object?> params;
      if (projectId != null) {
        sql = 'SELECT $_columns FROM rules '
            'WHERE is_latest AND key = :key AND project_id = :pid::uuid LIMIT 1';
        params = {'key': key, 'pid': projectId.value};
      } else if (productId != null) {
        sql = 'SELECT $_columns FROM rules '
            'WHERE is_latest AND key = :key AND project_id IS NULL AND product_id = :prodid::uuid LIMIT 1';
        params = {'key': key, 'prodid': productId.value};
      } else {
        return null;
      }
      final result = await _database.select(SqlStatement(sql, params));
      if (result.rows.isEmpty) return null;
      return DatabaseRuleMapper.fromRow(result.rows.first);
    } on DatabaseFailure catch (error) {
      throw DatasourceRuleFailure(errorMessage: error.errorMessage, stackTrace: StackTrace.current);
    }
  }

  @override
  Future<List<RuleNeighbor>> nearestByEmbedding({
    IdVO? productId,
    IdVO? projectId,
    required List<double> embedding,
    required String embeddingModel,
    IdVO? excludeId,
    double? maxDistance,
    int? limit,
  }) async {
    try {
      final params = <String, Object?>{
        'vec': SqlVector(embedding),
        'model': embeddingModel,
        // Tight default so the signal only fires on genuinely near-duplicate
        // rules, not every thematically related rule.
        'maxd': maxDistance ?? 0.12,
        'lim': limit ?? 3,
        'xid': excludeId?.value,
      };
      final String owner;
      if (projectId != null) {
        owner = 'project_id = :pid::uuid';
        params['pid'] = projectId.value;
      } else if (productId != null) {
        owner = 'project_id IS NULL AND product_id = :prodid::uuid';
        params['prodid'] = productId.value;
      } else {
        return const [];
      }
      // Same-model only; excludes the just-saved row and retired rules.
      final sql = 'SELECT $_columns, (embedding <=> :vec::vector(1024)) AS distance '
          'FROM rules '
          'WHERE is_latest AND retired_at IS NULL AND embedding IS NOT NULL '
          'AND embedding_model = :model AND $owner '
          'AND (:xid::uuid IS NULL OR id <> :xid::uuid) '
          'AND (embedding <=> :vec::vector(1024)) < :maxd '
          'ORDER BY distance LIMIT :lim';
      final result = await _database.select(SqlStatement(sql, params));
      return result.rows
          .map((r) => RuleNeighbor(
                rule: DatabaseRuleMapper.fromRow(r),
                distance: r['distance']?.toDouble() ?? 1.0,
              ))
          .toList();
    } on DatabaseFailure catch (error) {
      throw DatasourceRuleFailure(errorMessage: error.errorMessage, stackTrace: StackTrace.current);
    }
  }

  @override
  Future<List<RuleEntity>> rulesForTask(RulesForTaskQuery query) async {
    try {
      final params = <String, Object?>{'pid': query.projectId.value, 'limit': query.limit};
      var scopeFilter = '';
      if (query.scope != null && query.scope!.trim().isNotEmpty) {
        scopeFilter = 'AND scope = :scope';
        params['scope'] = query.scope!.trim();
      }

      // Inheritance: project rules + product rules of the project's product.
      // Override: DISTINCT ON (key) keeps the project-scoped rule per key.
      final sql = 'SELECT * FROM ('
          'SELECT DISTINCT ON (key) $_columns FROM rules '
          'WHERE is_latest '
          'AND (project_id = :pid::uuid '
          'OR (project_id IS NULL AND product_id = (SELECT product_id FROM projects WHERE id = :pid::uuid))) '
          '$scopeFilter '
          'ORDER BY key, (project_id IS NOT NULL) DESC'
          ') t '
          "ORDER BY (severity = 'required') DESC, priority ASC, title "
          'LIMIT :limit';

      final result = await _database.select(SqlStatement(sql, params));
      return result.rows.map(DatabaseRuleMapper.fromRow).toList();
    } on DatabaseFailure catch (error) {
      throw DatasourceRuleFailure(errorMessage: error.errorMessage, stackTrace: StackTrace.current);
    }
  }

  @override
  Future<List<RuleSearchResult>> searchRules(RuleSearchFilter filter) async {
    try {
      final hasText = filter.query.trim().isNotEmpty;
      final hasVec = filter.queryEmbedding != null && filter.queryEmbedding!.isNotEmpty;

      var mode = filter.mode;
      if (mode == RuleSearchMode.hybrid) {
        mode = (hasVec && hasText)
            ? RuleSearchMode.hybrid
            : (hasVec ? RuleSearchMode.semantic : RuleSearchMode.keyword);
      }
      if (mode == RuleSearchMode.semantic && !hasVec) return const [];
      if (mode == RuleSearchMode.keyword && !hasText) return const [];

      final params = <String, Object?>{'limit': filter.limit};
      final scope = <String>['m.is_latest'];
      if (filter.projectId != null && filter.productId != null) {
        scope.add('(m.project_id = :pid::uuid OR m.product_id = :prodid::uuid)');
        params['pid'] = filter.projectId!.value;
        params['prodid'] = filter.productId!.value;
      } else if (filter.projectId != null) {
        scope.add('m.project_id = :pid::uuid');
        params['pid'] = filter.projectId!.value;
      } else if (filter.productId != null) {
        scope.add('m.product_id = :prodid::uuid');
        params['prodid'] = filter.productId!.value;
      }
      if (filter.scope != null && filter.scope!.trim().isNotEmpty) {
        scope.add('m.scope = :rscope');
        params['rscope'] = filter.scope!.trim();
      }
      if (filter.severities.isNotEmpty) {
        scope.add('m.severity = ANY(:severities)');
        params['severities'] = filter.severities.map((s) => s.code).toList();
      }

      final ctes = <String>[
        'scoped AS (SELECT id, embedding, embedding_model, fts FROM rules m '
            'WHERE ${scope.join(' AND ')})',
      ];
      final fused = <String>[];

      if (mode == RuleSearchMode.semantic || mode == RuleSearchMode.hybrid) {
        final semWhere = <String>['embedding IS NOT NULL'];
        if (filter.queryModel != null && filter.queryModel!.isNotEmpty) {
          semWhere.add('embedding_model = :qmodel');
          params['qmodel'] = filter.queryModel;
        }
        ctes.add(
          'semantic AS (SELECT id, ROW_NUMBER() OVER (ORDER BY embedding <=> :qvec::vector(1024)) AS rnk '
          'FROM scoped WHERE ${semWhere.join(' AND ')} ORDER BY rnk LIMIT $_candidatePool)',
        );
        fused.add('SELECT id, 1.0/($_rrfK + rnk) AS s FROM semantic');
        params['qvec'] = SqlVector(filter.queryEmbedding!);
      }
      if (mode == RuleSearchMode.keyword || mode == RuleSearchMode.hybrid) {
        ctes.add(
          "lexical AS (SELECT id, ROW_NUMBER() OVER (ORDER BY ts_rank_cd(fts, websearch_to_tsquery('english', :q)) DESC) AS rnk "
          "FROM scoped WHERE fts @@ websearch_to_tsquery('english', :q) ORDER BY rnk LIMIT $_candidatePool)",
        );
        fused.add('SELECT id, 1.0/($_rrfK + rnk) AS s FROM lexical');
        params['q'] = filter.query.trim();
      }
      ctes.add('fused AS (${fused.join(' UNION ALL ')})');

      final sql = 'WITH ${ctes.join(', ')} '
          'SELECT $_columnsM, SUM(f.s) AS score '
          'FROM fused f JOIN rules m ON m.id = f.id '
          'GROUP BY m.id ORDER BY score DESC, m.priority ASC LIMIT :limit';

      final result = await _database.select(SqlStatement(sql, params));
      return result.rows
          .map((row) => RuleSearchResult(
                rule: DatabaseRuleMapper.fromRow(row),
                score: row['score']?.toDouble() ?? 0,
              ))
          .toList();
    } on DatabaseFailure catch (error) {
      throw DatasourceRuleFailure(errorMessage: error.errorMessage, stackTrace: StackTrace.current);
    }
  }

  @override
  Future<RuleEntity> retireRule(IdVO id, {String? reason, bool hard = false}) async {
    try {
      // Capture the row first (also lets us return the last known state on purge).
      final current = await _selectById(id);
      if (hard) {
        await _database.executeUpdate(
          SqlStatement('DELETE FROM rules WHERE id = :id::uuid', {'id': id.value}),
        );
        return current;
      }
      // Soft retire: drop it out of every recall path (is_latest=false) and
      // record why. Distinct from supersession by the non-null retired_at.
      final result = await _database.executeUpdate(SqlStatement(
        'UPDATE rules SET is_latest = false, retired_at = now(), '
        'retired_reason = :reason, updated_at = now() '
        'WHERE id = :id::uuid RETURNING $_columns',
        {'id': id.value, 'reason': reason},
      ));
      return DatabaseRuleMapper.fromRow(result.rows.first);
    } on DatabaseFailure catch (error) {
      throw DatasourceRuleFailure(errorMessage: error.errorMessage, stackTrace: StackTrace.current);
    }
  }

  @override
  Future<RuleEntity> setRulePriority(IdVO id, int priority) async {
    try {
      // Lightweight, in-place metadata update — NOT a supersession (no new
      // version row), so re-ranking a rule does not pollute its history.
      final result = await _database.executeUpdate(SqlStatement(
        'UPDATE rules SET priority = :priority, updated_at = now() '
        'WHERE id = :id::uuid RETURNING $_columns',
        {'id': id.value, 'priority': priority},
      ));
      if (result.rows.isEmpty) throw RuleNotFoundFailure(stackTrace: StackTrace.current);
      return DatabaseRuleMapper.fromRow(result.rows.first);
    } on DatabaseFailure catch (error) {
      throw DatasourceRuleFailure(errorMessage: error.errorMessage, stackTrace: StackTrace.current);
    }
  }

  Future<RuleEntity> _selectById(IdVO id) async {
    final result = await _database.select(
      SqlStatement('SELECT $_columns FROM rules WHERE id = :id::uuid', {'id': id.value}),
    );
    if (result.rows.isEmpty) throw RuleNotFoundFailure(stackTrace: StackTrace.current);
    return DatabaseRuleMapper.fromRow(result.rows.first);
  }
}
