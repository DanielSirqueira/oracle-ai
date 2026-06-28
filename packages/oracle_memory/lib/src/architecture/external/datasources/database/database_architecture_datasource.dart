import 'package:oracle_core/oracle_core.dart';

import '../../../domain/dtos/filters/architecture_search_filter.dart';
import '../../../domain/dtos/architecture_search_result.dart';
import '../../../domain/entities/architecture_entity.dart';
import '../../../domain/errors/architecture_failure.dart';
import '../../../infra/datasources/architecture_datasource.dart';
import '../../mappers/database/database_architecture_mapper.dart';

class DatabaseArchitectureDatasource implements ArchitectureDatasource {
  final Database _database;
  const DatabaseArchitectureDatasource({required Database database}) : _database = database;

  static const _columns =
      'id, project_id, area, content, embedding::text AS embedding, embedding_model, '
      'is_latest, supersedes, created_at, updated_at';

  static const _columnsM =
      'm.id, m.project_id, m.area, m.content, m.embedding::text AS embedding, m.embedding_model, '
      'm.is_latest, m.supersedes, m.created_at, m.updated_at';

  static const _rrfK = 60;
  static const _candidatePool = 50;

  @override
  Future<ArchitectureEntity> saveArchitecture(ArchitectureEntity architecture) async {
    try {
      final results = await _database.executeSavePoint([
        SavePointQuery(
          statement: SqlStatement(
            'UPDATE architectures SET is_latest = false '
            'WHERE is_latest AND project_id = :pid::uuid AND area = :area',
            {'pid': architecture.projectId.value, 'area': architecture.area},
          ),
        ),
        SavePointQuery(
          statement: SqlStatement(
            'INSERT INTO architectures (project_id, area, content, embedding, embedding_model, supersedes) '
            'VALUES (:project_id::uuid, :area, :content, :embedding::vector(1024), :embedding_model, :supersedes::uuid) '
            'RETURNING id, created_at, updated_at',
            DatabaseArchitectureMapper.toInsertParams(architecture),
          ),
        ),
      ]);
      final row = results.last.rows.first;
      return architecture.copyWith(
        id: IdVO(row['id']!.toText()!),
        createdAt: row['created_at']?.toDateTime(),
        updatedAt: row['updated_at']?.toDateTime(),
      );
    } on DatabaseFailure catch (error) {
      throw DatasourceArchitectureFailure(errorMessage: error.errorMessage, stackTrace: StackTrace.current);
    }
  }

  @override
  Future<ArchitectureEntity> getByArea(IdVO projectId, String area) async {
    try {
      final result = await _database.select(SqlStatement(
        'SELECT $_columns FROM architectures '
        'WHERE is_latest AND project_id = :pid::uuid AND area = :area',
        {'pid': projectId.value, 'area': area},
      ));
      if (result.rows.isEmpty) {
        throw ArchitectureNotFoundFailure(stackTrace: StackTrace.current);
      }
      return DatabaseArchitectureMapper.fromRow(result.rows.first);
    } on DatabaseFailure catch (error) {
      throw DatasourceArchitectureFailure(errorMessage: error.errorMessage, stackTrace: StackTrace.current);
    }
  }

  @override
  Future<List<ArchitectureSearchResult>> searchArchitecture(ArchitectureSearchFilter filter) async {
    try {
      final hasText = filter.query.trim().isNotEmpty;
      final hasVec = filter.queryEmbedding != null && filter.queryEmbedding!.isNotEmpty;

      var mode = filter.mode;
      if (mode == ArchitectureSearchMode.hybrid) {
        mode = (hasVec && hasText)
            ? ArchitectureSearchMode.hybrid
            : (hasVec ? ArchitectureSearchMode.semantic : ArchitectureSearchMode.keyword);
      }
      if (mode == ArchitectureSearchMode.semantic && !hasVec) return const [];
      if (mode == ArchitectureSearchMode.keyword && !hasText) return const [];

      final params = <String, Object?>{'limit': filter.limit};
      final scope = <String>['m.is_latest'];
      if (filter.projectId != null) {
        scope.add('m.project_id = :pid::uuid');
        params['pid'] = filter.projectId!.value;
      }
      if (filter.area != null && filter.area!.trim().isNotEmpty) {
        scope.add('m.area = :area');
        params['area'] = filter.area!.trim();
      }

      // architectures has no fts column, so we build the tsvector inline.
      final ctes = <String>[
        "scoped AS (SELECT id, embedding, "
            "to_tsvector('english', coalesce(area,'') || ' ' || coalesce(content,'')) AS fts "
            "FROM architectures m WHERE ${scope.join(' AND ')})",
      ];
      final fused = <String>[];

      if (mode == ArchitectureSearchMode.semantic || mode == ArchitectureSearchMode.hybrid) {
        ctes.add(
          'semantic AS (SELECT id, ROW_NUMBER() OVER (ORDER BY embedding <=> :qvec::vector(1024)) AS rnk '
          'FROM scoped WHERE embedding IS NOT NULL LIMIT $_candidatePool)',
        );
        fused.add('SELECT id, 1.0/($_rrfK + rnk) AS s FROM semantic');
        params['qvec'] = SqlVector(filter.queryEmbedding!);
      }
      if (mode == ArchitectureSearchMode.keyword || mode == ArchitectureSearchMode.hybrid) {
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
          'FROM fused f JOIN architectures m ON m.id = f.id '
          'GROUP BY m.id ORDER BY score DESC LIMIT :limit';

      final result = await _database.select(SqlStatement(sql, params));
      return result.rows
          .map((row) => ArchitectureSearchResult(
                architecture: DatabaseArchitectureMapper.fromRow(row),
                score: row['score']?.toDouble() ?? 0,
              ))
          .toList();
    } on DatabaseFailure catch (error) {
      throw DatasourceArchitectureFailure(errorMessage: error.errorMessage, stackTrace: StackTrace.current);
    }
  }

  @override
  Future<ArchitectureEntity> retireArchitecture(
    IdVO id, {
    String? reason,
    bool hard = false,
  }) async {
    try {
      final current = await _selectById(id);
      if (hard) {
        await _database.executeUpdate(
          SqlStatement('DELETE FROM architectures WHERE id = :id::uuid', {'id': id.value}),
        );
        return current;
      }
      final result = await _database.executeUpdate(SqlStatement(
        'UPDATE architectures SET is_latest = false, retired_at = now(), '
        'retired_reason = :reason, updated_at = now() '
        'WHERE id = :id::uuid RETURNING $_columns',
        {'id': id.value, 'reason': reason},
      ));
      return DatabaseArchitectureMapper.fromRow(result.rows.first);
    } on DatabaseFailure catch (error) {
      throw DatasourceArchitectureFailure(errorMessage: error.errorMessage, stackTrace: StackTrace.current);
    }
  }

  Future<ArchitectureEntity> _selectById(IdVO id) async {
    final result = await _database.select(
      SqlStatement('SELECT $_columns FROM architectures WHERE id = :id::uuid', {'id': id.value}),
    );
    if (result.rows.isEmpty) throw ArchitectureNotFoundFailure(stackTrace: StackTrace.current);
    return DatabaseArchitectureMapper.fromRow(result.rows.first);
  }
}
