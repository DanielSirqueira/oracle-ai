import 'package:oracle_core/oracle_core.dart';

import '../../../domain/dtos/filters/memory_search_filter.dart';
import '../../../domain/dtos/memory_neighbor.dart';
import '../../../domain/dtos/memory_search_result.dart';
import '../../../domain/entities/memory_entity.dart';
import '../../../domain/errors/memory_failure.dart';
import '../../../infra/datasources/memory_datasource.dart';
import '../../mappers/database/database_memory_mapper.dart';

/// PostgreSQL + pgvector backed [MemoryDatasource].
///
/// [searchMemories] performs a hybrid search: the semantic leg ranks by vector
/// distance (`<=>`), the lexical leg by `tsvector` rank, and the two are fused
/// with Reciprocal Rank Fusion (RRF, k=60). The mode degrades gracefully when
/// only a query or only an embedding is supplied.
class DatabaseMemoryDatasource implements MemoryDatasource {
  final Database _database;
  const DatabaseMemoryDatasource({required Database database}) : _database = database;

  // The pgvector `vector` type is returned by the driver as binary; cast it to
  // text (`[1,0,...]`) so DataRowType.toVector() can parse it on read.
  static const _columns =
      'id, organization_id, project_id, module_id, key, tier, kind, title, body, tags, importance, '
      'embedding::text AS embedding, embedding_model, is_latest, supersedes, created_at, updated_at';

  static const _columnsM =
      'm.id, m.organization_id, m.project_id, m.module_id, m.key, m.tier, m.kind, m.title, m.body, '
      'm.tags, m.importance, m.embedding::text AS embedding, m.embedding_model, m.is_latest, '
      'm.supersedes, m.created_at, m.updated_at';

  static const _rrfK = 60;
  static const _candidatePool = 50;

  @override
  Future<MemoryEntity> saveMemory(MemoryEntity memory) async {
    try {
      final queries = <SavePointQuery>[
        // Explicit supersession: when the caller passes `supersedes`, retire that
        // row (flip is_latest + stamp superseded_at). No-op when supersedes is null.
        SavePointQuery(
          statement: SqlStatement(
            'UPDATE memories SET is_latest = false, superseded_at = now() '
            'WHERE is_latest AND id = :sid::uuid',
            {'sid': memory.supersedes?.value},
          ),
        ),
      ];

      // Keyed supersession: retire the current latest memory with the same key in
      // the same owner, so the (owner, key) unique index holds and re-saving a key
      // updates one memory instead of piling up near-duplicates. No-op for keyless
      // memories, which keep the old append-only behavior.
      final key = memory.key?.trim();
      if (key != null && key.isNotEmpty) {
        final String sql;
        final Map<String, Object?> params;
        // Supersede within the SAME owner level (module > project > organization).
        if (memory.moduleId != null) {
          sql = 'UPDATE memories SET is_latest = false, superseded_at = now() '
              'WHERE is_latest AND key = :key AND module_id = :mid::uuid';
          params = {'key': key, 'mid': memory.moduleId!.value};
        } else if (memory.projectId != null) {
          sql = 'UPDATE memories SET is_latest = false, superseded_at = now() '
              'WHERE is_latest AND key = :key AND module_id IS NULL AND project_id = :pid::uuid';
          params = {'key': key, 'pid': memory.projectId!.value};
        } else {
          sql = 'UPDATE memories SET is_latest = false, superseded_at = now() '
              'WHERE is_latest AND key = :key AND module_id IS NULL AND project_id IS NULL '
              'AND organization_id = :prodid::uuid';
          params = {'key': key, 'prodid': memory.organizationId!.value};
        }
        queries.add(SavePointQuery(statement: SqlStatement(sql, params)));
      }

      queries.add(SavePointQuery(
        statement: SqlStatement(
          'INSERT INTO memories '
          '(organization_id, project_id, module_id, key, tier, kind, title, body, tags, importance, '
          'embedding, embedding_model, supersedes) '
          'VALUES (:organization_id::uuid, :project_id::uuid, :module_id::uuid, :key, :tier, :kind, '
          ':title, :body, :tags, :importance, :embedding::vector(1024), :embedding_model, :supersedes::uuid) '
          'RETURNING id, created_at, updated_at',
          DatabaseMemoryMapper.toInsertParams(memory),
        ),
      ));

      final results = await _database.executeSavePoint(queries);
      final row = results.last.rows.first;
      return memory.copyWith(
        id: IdVO(row['id']!.toText()!),
        createdAt: row['created_at']?.toDateTime(),
        updatedAt: row['updated_at']?.toDateTime(),
      );
    } on DatabaseFailure catch (error) {
      throw DatasourceMemoryFailure(errorMessage: error.errorMessage, stackTrace: StackTrace.current);
    }
  }

  @override
  Future<MemoryEntity?> currentByKey({IdVO? organizationId, IdVO? projectId, required String key}) async {
    try {
      final String sql;
      final Map<String, Object?> params;
      if (projectId != null) {
        sql = 'SELECT $_columns FROM memories '
            'WHERE is_latest AND key = :key AND project_id = :pid::uuid LIMIT 1';
        params = {'key': key, 'pid': projectId.value};
      } else if (organizationId != null) {
        sql = 'SELECT $_columns FROM memories '
            'WHERE is_latest AND key = :key AND project_id IS NULL AND organization_id = :prodid::uuid LIMIT 1';
        params = {'key': key, 'prodid': organizationId.value};
      } else {
        return null;
      }
      final result = await _database.select(SqlStatement(sql, params));
      if (result.rows.isEmpty) return null;
      return DatabaseMemoryMapper.fromRow(result.rows.first);
    } on DatabaseFailure catch (error) {
      throw DatasourceMemoryFailure(errorMessage: error.errorMessage, stackTrace: StackTrace.current);
    }
  }

  @override
  Future<List<MemoryNeighbor>> nearestByEmbedding({
    IdVO? organizationId,
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
        // Tight default: only surface genuinely near-duplicate memories (the
        // real dup clusters sit under ~0.12 cosine), not every related memory,
        // so the signal stays high-value instead of firing on most saves.
        'maxd': maxDistance ?? 0.12,
        'lim': limit ?? 3,
        'xid': excludeId?.value,
      };
      final String owner;
      if (projectId != null) {
        owner = 'project_id = :pid::uuid';
        params['pid'] = projectId.value;
      } else if (organizationId != null) {
        owner = 'project_id IS NULL AND organization_id = :prodid::uuid';
        params['prodid'] = organizationId.value;
      } else {
        return const [];
      }
      // Same-model only: cross-model cosine distances are meaningless. Excludes
      // the just-saved row and any soft-forgotten memory.
      final sql = 'SELECT $_columns, (embedding <=> :vec::vector(1024)) AS distance '
          'FROM memories '
          'WHERE is_latest AND retired_at IS NULL AND embedding IS NOT NULL '
          'AND embedding_model = :model AND $owner '
          'AND (:xid::uuid IS NULL OR id <> :xid::uuid) '
          'AND (embedding <=> :vec::vector(1024)) < :maxd '
          'ORDER BY distance LIMIT :lim';
      final result = await _database.select(SqlStatement(sql, params));
      return result.rows
          .map((r) => MemoryNeighbor(
                memory: DatabaseMemoryMapper.fromRow(r),
                distance: r['distance']?.toDouble() ?? 1.0,
              ))
          .toList();
    } on DatabaseFailure catch (error) {
      throw DatasourceMemoryFailure(errorMessage: error.errorMessage, stackTrace: StackTrace.current);
    }
  }

  @override
  Future<MemoryEntity> getMemoryById(IdVO id) async {
    try {
      // Reading a memory is an access event — bump the decay substrate
      // (access_count / last_accessed_at) so forgetting can weigh recency of use.
      final result = await _database.executeUpdate(SqlStatement(
        'UPDATE memories SET access_count = access_count + 1, last_accessed_at = now() '
        'WHERE id = :id::uuid RETURNING $_columns',
        {'id': id.value},
      ));
      if (result.rows.isEmpty) {
        throw MemoryNotFoundFailure(stackTrace: StackTrace.current);
      }
      return DatabaseMemoryMapper.fromRow(result.rows.first);
    } on DatabaseFailure catch (error) {
      throw DatasourceMemoryFailure(errorMessage: error.errorMessage, stackTrace: StackTrace.current);
    }
  }

  @override
  Future<MemoryEntity> forgetMemory(IdVO id, {String? reason, bool hard = false}) async {
    try {
      final current = await _selectById(id);
      if (hard) {
        await _database.executeUpdate(
          SqlStatement('DELETE FROM memories WHERE id = :id::uuid', {'id': id.value}),
        );
        return current;
      }
      final result = await _database.executeUpdate(SqlStatement(
        'UPDATE memories SET is_latest = false, retired_at = now(), '
        'retired_reason = :reason, updated_at = now() '
        'WHERE id = :id::uuid RETURNING $_columns',
        {'id': id.value, 'reason': reason},
      ));
      return DatabaseMemoryMapper.fromRow(result.rows.first);
    } on DatabaseFailure catch (error) {
      throw DatasourceMemoryFailure(errorMessage: error.errorMessage, stackTrace: StackTrace.current);
    }
  }

  @override
  Future<List<MemoryEntity>> topMemories(IdVO projectId, int limit) async {
    try {
      final result = await _database.select(SqlStatement(
        'SELECT $_columns FROM memories '
        'WHERE is_latest AND retired_at IS NULL AND project_id = :pid::uuid '
        'ORDER BY importance DESC, created_at DESC LIMIT :lim',
        {'pid': projectId.value, 'lim': limit},
      ));
      final memories = result.rows.map(DatabaseMemoryMapper.fromRow).toList();
      await _bumpAccess(memories.map((m) => m.id.value).toList());
      return memories;
    } on DatabaseFailure catch (error) {
      throw DatasourceMemoryFailure(errorMessage: error.errorMessage, stackTrace: StackTrace.current);
    }
  }

  @override
  Future<List<MemoryEntity>> relevantMemories(
    IdVO projectId,
    List<double> queryEmbedding,
    double maxDistance,
    int limit, {
    String? queryModel,
  }) async {
    try {
      final params = <String, Object?>{
        'pid': projectId.value,
        'qvec': SqlVector(queryEmbedding),
        'maxd': maxDistance,
        'lim': limit,
      };
      // Only compare against same-model vectors when the caller declares the
      // query's model (cross-model cosine distances are meaningless).
      var modelFilter = '';
      if (queryModel != null && queryModel.isNotEmpty) {
        modelFilter = 'AND embedding_model = :qmodel ';
        params['qmodel'] = queryModel;
      }
      final result = await _database.select(SqlStatement(
        'SELECT $_columns FROM memories '
        'WHERE is_latest AND retired_at IS NULL AND project_id = :pid::uuid '
        'AND embedding IS NOT NULL $modelFilter'
        'AND (embedding <=> :qvec::vector(1024)) < :maxd '
        'ORDER BY embedding <=> :qvec::vector(1024) LIMIT :lim',
        params,
      ));
      final memories = result.rows.map(DatabaseMemoryMapper.fromRow).toList();
      await _bumpAccess(memories.map((m) => m.id.value).toList());
      return memories;
    } on DatabaseFailure catch (error) {
      throw DatasourceMemoryFailure(errorMessage: error.errorMessage, stackTrace: StackTrace.current);
    }
  }

  /// Bumps `access_count` / `last_accessed_at` for the given memory ids. Called
  /// from every recall path so the decay sweep sees real usage. Best-effort: a
  /// failure here must never fail the recall it is accounting for.
  Future<void> _bumpAccess(List<String> ids) async {
    if (ids.isEmpty) return;
    try {
      // Cast the PARAMETER (text[] -> uuid[]), never the column: `id::text` would
      // defeat the uuid primary-key index and force a full-table scan per recall.
      await _database.executeUpdate(SqlStatement(
        'UPDATE memories SET access_count = access_count + 1, last_accessed_at = now() '
        'WHERE id = ANY(:ids::uuid[])',
        {'ids': ids},
      ));
    } catch (_) {/* accounting is best-effort */}
  }

  Future<MemoryEntity> _selectById(IdVO id) async {
    final result = await _database.select(
      SqlStatement('SELECT $_columns FROM memories WHERE id = :id::uuid', {'id': id.value}),
    );
    if (result.rows.isEmpty) throw MemoryNotFoundFailure(stackTrace: StackTrace.current);
    return DatabaseMemoryMapper.fromRow(result.rows.first);
  }

  @override
  Future<List<MemorySearchResult>> searchMemories(MemorySearchFilter filter) async {
    try {
      final hasText = filter.query.trim().isNotEmpty;
      final hasVec = filter.queryEmbedding != null && filter.queryEmbedding!.isNotEmpty;

      // Resolve effective mode (hybrid degrades to whatever input is available).
      var mode = filter.mode;
      if (mode == SearchMode.hybrid) {
        mode = (hasVec && hasText)
            ? SearchMode.hybrid
            : (hasVec ? SearchMode.semantic : SearchMode.keyword);
      }
      if (mode == SearchMode.semantic && !hasVec) return const [];
      if (mode == SearchMode.keyword && !hasText) return const [];

      final params = <String, Object?>{'limit': filter.limit};

      // Scope predicate (alias `m` inside the `scoped` CTE). Recall unions the
      // three levels the caller passes — module, project, organization — so a
      // module search also surfaces its project's and organization's knowledge.
      final scope = <String>['m.is_latest'];
      final owners = <String>[];
      if (filter.moduleId != null) {
        owners.add('m.module_id = :mid::uuid');
        params['mid'] = filter.moduleId!.value;
      }
      if (filter.projectId != null) {
        owners.add('m.project_id = :pid::uuid');
        params['pid'] = filter.projectId!.value;
      }
      if (filter.organizationId != null) {
        owners.add('m.organization_id = :prodid::uuid');
        params['prodid'] = filter.organizationId!.value;
      }
      if (owners.isNotEmpty) scope.add('(${owners.join(' OR ')})');
      if (filter.tiers.isNotEmpty) {
        scope.add('m.tier = ANY(:tiers)');
        params['tiers'] = filter.tiers.map((t) => t.code).toList();
      }
      if (filter.kinds.isNotEmpty) {
        scope.add('m.kind = ANY(:kinds)');
        params['kinds'] = filter.kinds.map((k) => k.code).toList();
      }

      final ctes = <String>[
        'scoped AS (SELECT id, embedding, embedding_model, fts FROM memories m '
            'WHERE ${scope.join(' AND ')})',
      ];
      final fused = <String>[];

      if (mode == SearchMode.semantic || mode == SearchMode.hybrid) {
        final semWhere = <String>['embedding IS NOT NULL'];
        if (filter.queryModel != null && filter.queryModel!.isNotEmpty) {
          semWhere.add('embedding_model = :qmodel');
          params['qmodel'] = filter.queryModel;
        }
        // ORDER BY rnk makes the LIMIT deterministically keep the top-ranked
        // candidates (a bare LIMIT over a window function is not guaranteed to).
        ctes.add(
          'semantic AS (SELECT id, ROW_NUMBER() OVER (ORDER BY embedding <=> :qvec::vector(1024)) AS rnk '
          'FROM scoped WHERE ${semWhere.join(' AND ')} ORDER BY rnk LIMIT $_candidatePool)',
        );
        fused.add('SELECT id, 1.0/($_rrfK + rnk) AS s FROM semantic');
        params['qvec'] = SqlVector(filter.queryEmbedding!);
      }
      if (mode == SearchMode.keyword || mode == SearchMode.hybrid) {
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
          'FROM fused f JOIN memories m ON m.id = f.id '
          'GROUP BY m.id ORDER BY score DESC, m.importance DESC, m.created_at DESC LIMIT :limit';

      final result = await _database.select(SqlStatement(sql, params));
      final results = result.rows
          .map((row) => MemorySearchResult(
                memory: DatabaseMemoryMapper.fromRow(row),
                score: row['score']?.toDouble() ?? 0,
              ))
          .toList();
      // Recall is an access event: bump the decay substrate so memories that are
      // actually surfaced don't look "cold" to the maintenance decay sweep.
      await _bumpAccess(results.map((r) => r.memory.id.value).toList());
      return results;
    } on DatabaseFailure catch (error) {
      throw DatasourceMemoryFailure(errorMessage: error.errorMessage, stackTrace: StackTrace.current);
    }
  }
}
