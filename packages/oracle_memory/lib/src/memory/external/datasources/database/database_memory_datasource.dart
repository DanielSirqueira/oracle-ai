import 'package:oracle_core/oracle_core.dart';

import '../../../domain/dtos/filters/memory_search_filter.dart';
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
      'id, product_id, project_id, tier, kind, title, body, tags, importance, '
      'embedding::text AS embedding, embedding_model, is_latest, supersedes, created_at, updated_at';

  static const _columnsM =
      'm.id, m.product_id, m.project_id, m.tier, m.kind, m.title, m.body, m.tags, '
      'm.importance, m.embedding::text AS embedding, m.embedding_model, m.is_latest, '
      'm.supersedes, m.created_at, m.updated_at';

  static const _rrfK = 60;
  static const _candidatePool = 50;

  @override
  Future<MemoryEntity> saveMemory(MemoryEntity memory) async {
    try {
      // Unlike rules/architectures, memories have no natural key, so supersession
      // is explicit: when the caller passes `supersedes`, retire that row in the
      // same transaction (flip is_latest + stamp superseded_at) so both versions
      // don't surface as latest. When supersedes is null, the UPDATE is a no-op.
      final results = await _database.executeSavePoint([
        SavePointQuery(
          statement: SqlStatement(
            'UPDATE memories SET is_latest = false, superseded_at = now() '
            'WHERE is_latest AND id = :sid::uuid',
            {'sid': memory.supersedes?.value},
          ),
        ),
        SavePointQuery(
          statement: SqlStatement(
            'INSERT INTO memories '
            '(product_id, project_id, tier, kind, title, body, tags, importance, '
            'embedding, embedding_model, supersedes) '
            'VALUES (:product_id::uuid, :project_id::uuid, :tier, :kind, :title, :body, '
            ':tags, :importance, :embedding::vector(1024), :embedding_model, :supersedes::uuid) '
            'RETURNING id, created_at, updated_at',
            DatabaseMemoryMapper.toInsertParams(memory),
          ),
        ),
      ]);
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
      return result.rows.map(DatabaseMemoryMapper.fromRow).toList();
    } on DatabaseFailure catch (error) {
      throw DatasourceMemoryFailure(errorMessage: error.errorMessage, stackTrace: StackTrace.current);
    }
  }

  @override
  Future<List<MemoryEntity>> relevantMemories(
    IdVO projectId,
    List<double> queryEmbedding,
    double maxDistance,
    int limit,
  ) async {
    try {
      final result = await _database.select(SqlStatement(
        'SELECT $_columns FROM memories '
        'WHERE is_latest AND retired_at IS NULL AND project_id = :pid::uuid '
        'AND embedding IS NOT NULL AND (embedding <=> :qvec::vector(1024)) < :maxd '
        'ORDER BY embedding <=> :qvec::vector(1024) LIMIT :lim',
        {
          'pid': projectId.value,
          'qvec': SqlVector(queryEmbedding),
          'maxd': maxDistance,
          'lim': limit,
        },
      ));
      return result.rows.map(DatabaseMemoryMapper.fromRow).toList();
    } on DatabaseFailure catch (error) {
      throw DatasourceMemoryFailure(errorMessage: error.errorMessage, stackTrace: StackTrace.current);
    }
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

      // Scope predicate (alias `m` inside the `scoped` CTE).
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
      if (filter.tiers.isNotEmpty) {
        scope.add('m.tier = ANY(:tiers)');
        params['tiers'] = filter.tiers.map((t) => t.code).toList();
      }
      if (filter.kinds.isNotEmpty) {
        scope.add('m.kind = ANY(:kinds)');
        params['kinds'] = filter.kinds.map((k) => k.code).toList();
      }

      final ctes = <String>[
        'scoped AS (SELECT id, embedding, fts FROM memories m WHERE ${scope.join(' AND ')})',
      ];
      final fused = <String>[];

      if (mode == SearchMode.semantic || mode == SearchMode.hybrid) {
        ctes.add(
          'semantic AS (SELECT id, ROW_NUMBER() OVER (ORDER BY embedding <=> :qvec::vector(1024)) AS rnk '
          'FROM scoped WHERE embedding IS NOT NULL LIMIT $_candidatePool)',
        );
        fused.add('SELECT id, 1.0/($_rrfK + rnk) AS s FROM semantic');
        params['qvec'] = SqlVector(filter.queryEmbedding!);
      }
      if (mode == SearchMode.keyword || mode == SearchMode.hybrid) {
        ctes.add(
          "lexical AS (SELECT id, ROW_NUMBER() OVER (ORDER BY ts_rank_cd(fts, websearch_to_tsquery('english', :q)) DESC) AS rnk "
          "FROM scoped WHERE fts @@ websearch_to_tsquery('english', :q) LIMIT $_candidatePool)",
        );
        fused.add('SELECT id, 1.0/($_rrfK + rnk) AS s FROM lexical');
        params['q'] = filter.query.trim();
      }
      ctes.add('fused AS (${fused.join(' UNION ALL ')})');

      final sql = 'WITH ${ctes.join(', ')} '
          'SELECT $_columnsM, SUM(f.s) AS score '
          'FROM fused f JOIN memories m ON m.id = f.id '
          'GROUP BY m.id ORDER BY score DESC LIMIT :limit';

      final result = await _database.select(SqlStatement(sql, params));
      return result.rows
          .map((row) => MemorySearchResult(
                memory: DatabaseMemoryMapper.fromRow(row),
                score: row['score']?.toDouble() ?? 0,
              ))
          .toList();
    } on DatabaseFailure catch (error) {
      throw DatasourceMemoryFailure(errorMessage: error.errorMessage, stackTrace: StackTrace.current);
    }
  }
}
