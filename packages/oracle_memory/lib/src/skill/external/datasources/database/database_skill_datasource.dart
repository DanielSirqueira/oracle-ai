import 'package:oracle_core/oracle_core.dart';

import '../../../domain/dtos/filters/skill_search_filter.dart';
import '../../../domain/dtos/skill_neighbor.dart';
import '../../../domain/dtos/skill_search_result.dart';
import '../../../domain/entities/skill_entity.dart';
import '../../../domain/errors/skill_failure.dart';
import '../../../infra/datasources/skill_datasource.dart';
import '../../mappers/database/database_skill_mapper.dart';

/// PostgreSQL + pgvector backed [SkillDatasource].
///
/// - [saveSkill]: supersedes the current latest skill with the same key in the
///   same owner (project, organization, or GLOBAL) in one transaction.
/// - [getSkillByKey]: override resolution — project wins over organization wins over
///   global — and bumps the usage substrate.
/// - [searchSkills]: hybrid search (vector + full-text, RRF), like memory/rule.
///   Global skills are always in scope; project/organization widen it.
class DatabaseSkillDatasource implements SkillDatasource {
  final Database _database;
  const DatabaseSkillDatasource({required Database database}) : _database = database;

  // `embedding::text` so DataRowType.toVector() can parse it (driver returns
  // the vector type as binary).
  static const _columns =
      'id, organization_id, project_id, key, name, description, content, tags, '
      'embedding::text AS embedding, embedding_model, is_latest, supersedes, created_at, updated_at';

  static const _columnsM =
      'm.id, m.organization_id, m.project_id, m.key, m.name, m.description, m.content, m.tags, '
      'm.embedding::text AS embedding, m.embedding_model, m.is_latest, m.supersedes, '
      'm.created_at, m.updated_at';

  static const _rrfK = 60;
  static const _candidatePool = 50;

  /// Owner predicate + params for a (project | organization | global) scope.
  static (String, Map<String, Object?>) _owner(IdVO? projectId, IdVO? organizationId) {
    if (projectId != null) {
      return ('project_id = :pid::uuid', {'pid': projectId.value});
    }
    if (organizationId != null) {
      return ('project_id IS NULL AND organization_id = :prodid::uuid', {'prodid': organizationId.value});
    }
    return ('project_id IS NULL AND organization_id IS NULL', const {});
  }

  @override
  Future<SkillEntity> saveSkill(SkillEntity skill) async {
    try {
      // 1) Supersede the current latest version of this key in the same owner.
      final (owner, ownerParams) = _owner(skill.projectId, skill.organizationId);
      final supersedeSql = 'UPDATE skills SET is_latest = false, updated_at = now() '
          'WHERE is_latest AND key = :key AND $owner';

      // 2) Insert the new version.
      const insertSql = 'INSERT INTO skills '
          '(organization_id, project_id, key, name, description, content, tags, '
          'embedding, embedding_model, supersedes) '
          'VALUES (:organization_id::uuid, :project_id::uuid, :key, :name, :description, :content, '
          ':tags, :embedding::vector(1024), :embedding_model, :supersedes::uuid) '
          'RETURNING id, created_at, updated_at';

      final results = await _database.executeSavePoint([
        SavePointQuery(
            statement: SqlStatement(supersedeSql, {'key': skill.key, ...ownerParams})),
        SavePointQuery(
            statement: SqlStatement(insertSql, DatabaseSkillMapper.toInsertParams(skill))),
      ]);
      final row = results.last.rows.first;
      return skill.copyWith(
        id: IdVO(row['id']!.toText()!),
        createdAt: row['created_at']?.toDateTime(),
        updatedAt: row['updated_at']?.toDateTime(),
      );
    } on DatabaseFailure catch (error) {
      throw DatasourceSkillFailure(errorMessage: error.errorMessage, stackTrace: StackTrace.current);
    }
  }

  @override
  Future<List<SkillNeighbor>> nearestByEmbedding({
    IdVO? organizationId,
    IdVO? projectId,
    required List<double> embedding,
    required String embeddingModel,
    IdVO? excludeId,
    double? maxDistance,
    int? limit,
  }) async {
    try {
      final (owner, ownerParams) = _owner(projectId, organizationId);
      final params = <String, Object?>{
        'vec': SqlVector(embedding),
        'model': embeddingModel,
        // Tight default so the signal only fires on genuinely near-duplicate
        // skills, not every thematically related one.
        'maxd': maxDistance ?? 0.12,
        'lim': limit ?? 3,
        'xid': excludeId?.value,
        ...ownerParams,
      };
      // Same-model only; excludes the just-saved row and retired skills.
      final sql = 'SELECT $_columns, (embedding <=> :vec::vector(1024)) AS distance '
          'FROM skills '
          'WHERE is_latest AND retired_at IS NULL AND embedding IS NOT NULL '
          'AND embedding_model = :model AND $owner '
          'AND (:xid::uuid IS NULL OR id <> :xid::uuid) '
          'AND (embedding <=> :vec::vector(1024)) < :maxd '
          'ORDER BY distance LIMIT :lim';
      final result = await _database.select(SqlStatement(sql, params));
      return result.rows
          .map((r) => SkillNeighbor(
                skill: DatabaseSkillMapper.fromRow(r),
                distance: r['distance']?.toDouble() ?? 1.0,
              ))
          .toList();
    } on DatabaseFailure catch (error) {
      throw DatasourceSkillFailure(errorMessage: error.errorMessage, stackTrace: StackTrace.current);
    }
  }

  @override
  Future<SkillEntity?> currentByKey({IdVO? organizationId, IdVO? projectId, required String key}) async {
    try {
      final (owner, ownerParams) = _owner(projectId, organizationId);
      final result = await _database.select(SqlStatement(
        'SELECT $_columns FROM skills WHERE is_latest AND retired_at IS NULL '
        'AND key = :key AND $owner LIMIT 1',
        {'key': key, ...ownerParams},
      ));
      if (result.rows.isEmpty) return null;
      return DatabaseSkillMapper.fromRow(result.rows.first);
    } on DatabaseFailure catch (error) {
      throw DatasourceSkillFailure(errorMessage: error.errorMessage, stackTrace: StackTrace.current);
    }
  }

  @override
  Future<SkillEntity> getSkillById(IdVO id) async {
    try {
      // Reading a skill is a usage event — bump the substrate so listings can
      // weigh which skills actually get used.
      final result = await _database.executeUpdate(SqlStatement(
        'UPDATE skills SET access_count = access_count + 1, last_accessed_at = now() '
        'WHERE id = :id::uuid RETURNING $_columns',
        {'id': id.value},
      ));
      if (result.rows.isEmpty) throw SkillNotFoundFailure(stackTrace: StackTrace.current);
      return DatabaseSkillMapper.fromRow(result.rows.first);
    } on DatabaseFailure catch (error) {
      throw DatasourceSkillFailure(errorMessage: error.errorMessage, stackTrace: StackTrace.current);
    }
  }

  @override
  Future<SkillEntity> getSkillByKey(String key, {IdVO? projectId, IdVO? organizationId}) async {
    try {
      // Override resolution in one query: candidate rows from any visible scope,
      // most specific first (project > organization > global).
      final params = <String, Object?>{
        'key': key,
        'pid': projectId?.value,
        'prodid': organizationId?.value,
      };
      final result = await _database.executeUpdate(SqlStatement(
        'UPDATE skills SET access_count = access_count + 1, last_accessed_at = now() '
        'WHERE id = ('
        '  SELECT id FROM skills WHERE is_latest AND retired_at IS NULL AND key = :key '
        '  AND (project_id = :pid::uuid '
        '       OR (project_id IS NULL AND organization_id = :prodid::uuid) '
        '       OR (project_id IS NULL AND organization_id IS NULL)) '
        '  ORDER BY (project_id IS NOT NULL) DESC, (organization_id IS NOT NULL) DESC '
        '  LIMIT 1'
        ') RETURNING $_columns',
        params,
      ));
      if (result.rows.isEmpty) throw SkillNotFoundFailure(stackTrace: StackTrace.current);
      return DatabaseSkillMapper.fromRow(result.rows.first);
    } on DatabaseFailure catch (error) {
      throw DatasourceSkillFailure(errorMessage: error.errorMessage, stackTrace: StackTrace.current);
    }
  }

  @override
  Future<List<SkillSearchResult>> searchSkills(SkillSearchFilter filter) async {
    try {
      final hasText = filter.query.trim().isNotEmpty;
      final hasVec = filter.queryEmbedding != null && filter.queryEmbedding!.isNotEmpty;

      var mode = filter.mode;
      if (mode == SkillSearchMode.hybrid) {
        mode = (hasVec && hasText)
            ? SkillSearchMode.hybrid
            : (hasVec ? SkillSearchMode.semantic : SkillSearchMode.keyword);
      }
      if (mode == SkillSearchMode.semantic && !hasVec) return const [];
      if (mode == SkillSearchMode.keyword && !hasText) return const [];

      final params = <String, Object?>{'limit': filter.limit};
      // Global skills are always visible; project/organization ADD to the scope
      // (unlike rules, where scope narrows) — the library is shared by design.
      final visible = <String>['(m.project_id IS NULL AND m.organization_id IS NULL)'];
      if (filter.projectId != null) {
        visible.add('m.project_id = :pid::uuid');
        params['pid'] = filter.projectId!.value;
      }
      if (filter.organizationId != null) {
        visible.add('(m.project_id IS NULL AND m.organization_id = :prodid::uuid)');
        params['prodid'] = filter.organizationId!.value;
      }
      final scope = 'm.is_latest AND m.retired_at IS NULL AND (${visible.join(' OR ')})';

      final ctes = <String>[
        'scoped AS (SELECT id, embedding, embedding_model, fts FROM skills m WHERE $scope)',
      ];
      final fused = <String>[];

      if (mode == SkillSearchMode.semantic || mode == SkillSearchMode.hybrid) {
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
      if (mode == SkillSearchMode.keyword || mode == SkillSearchMode.hybrid) {
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
          'FROM fused f JOIN skills m ON m.id = f.id '
          'GROUP BY m.id ORDER BY score DESC LIMIT :limit';

      final result = await _database.select(SqlStatement(sql, params));
      return result.rows
          .map((row) => SkillSearchResult(
                skill: DatabaseSkillMapper.fromRow(row),
                score: row['score']?.toDouble() ?? 0,
              ))
          .toList();
    } on DatabaseFailure catch (error) {
      throw DatasourceSkillFailure(errorMessage: error.errorMessage, stackTrace: StackTrace.current);
    }
  }

  @override
  Future<List<SkillEntity>> listSkills({IdVO? projectId, IdVO? organizationId, int limit = 200}) async {
    try {
      final params = <String, Object?>{'limit': limit};
      final visible = <String>['(project_id IS NULL AND organization_id IS NULL)'];
      if (projectId != null) {
        visible.add('project_id = :pid::uuid');
        params['pid'] = projectId.value;
      }
      if (organizationId != null) {
        visible.add('(project_id IS NULL AND organization_id = :prodid::uuid)');
        params['prodid'] = organizationId.value;
      }
      final result = await _database.select(SqlStatement(
        'SELECT $_columns FROM skills '
        'WHERE is_latest AND retired_at IS NULL AND (${visible.join(' OR ')}) '
        'ORDER BY key LIMIT :limit',
        params,
      ));
      return result.rows.map(DatabaseSkillMapper.fromRow).toList();
    } on DatabaseFailure catch (error) {
      throw DatasourceSkillFailure(errorMessage: error.errorMessage, stackTrace: StackTrace.current);
    }
  }

  @override
  Future<SkillEntity> retireSkill(IdVO id, {String? reason, bool hard = false}) async {
    try {
      final current = await _database.select(SqlStatement(
        'SELECT $_columns FROM skills WHERE id = :id::uuid',
        {'id': id.value},
      ));
      if (current.rows.isEmpty) throw SkillNotFoundFailure(stackTrace: StackTrace.current);
      if (hard) {
        await _database.executeUpdate(
          SqlStatement('DELETE FROM skills WHERE id = :id::uuid', {'id': id.value}),
        );
        return DatabaseSkillMapper.fromRow(current.rows.first);
      }
      // Soft retire: drop it from every recall path and record why. Distinct
      // from supersession by the non-null retired_at.
      final result = await _database.executeUpdate(SqlStatement(
        'UPDATE skills SET is_latest = false, retired_at = now(), '
        'retired_reason = :reason, updated_at = now() '
        'WHERE id = :id::uuid RETURNING $_columns',
        {'id': id.value, 'reason': reason},
      ));
      return DatabaseSkillMapper.fromRow(result.rows.first);
    } on DatabaseFailure catch (error) {
      throw DatasourceSkillFailure(errorMessage: error.errorMessage, stackTrace: StackTrace.current);
    }
  }
}
