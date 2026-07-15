import 'package:oracle_core/oracle_core.dart';

import '../../../domain/dtos/rfc_bundle.dart';
import '../../../domain/dtos/rfc_comment_neighbor.dart';
import '../../../domain/dtos/rfc_status_report.dart';
import '../../../domain/entities/rfc_comment_entity.dart';
import '../../../domain/entities/rfc_entity.dart';
import '../../../domain/entities/rfc_evidence_entity.dart';
import '../../../domain/entities/rfc_section_entity.dart';
import '../../../domain/entities/rfc_version_entity.dart';
import '../../../domain/enums/rfc_status.dart';
import '../../../domain/errors/rfc_failure.dart';
import '../../../infra/datasources/rfc_datasource.dart';
import '../../mappers/database/database_rfc_comment_mapper.dart';
import '../../mappers/database/database_rfc_evidence_mapper.dart';
import '../../mappers/database/database_rfc_mapper.dart';
import '../../mappers/database/database_rfc_section_mapper.dart';
import '../../mappers/database/database_rfc_version_mapper.dart';

/// PostgreSQL + pgvector backed [RfcDatasource].
///
/// [openRfc]/[reviseRfc] insert the RFC header, its version and sections in one
/// savepoint. Ids are generated client-side (uuid v7) so a single transaction
/// can wire the circular `rfcs.current_version_id` ↔ `rfc_versions.rfc_id`
/// relationship (insert the header with a NULL current version, insert the
/// version, then point the header at it).
class DatabaseRfcDatasource implements RfcDatasource {
  final Database _database;
  const DatabaseRfcDatasource({required Database database}) : _database = database;

  static const _rfcColumns =
      'id, organization_id, project_id, module_id, title, rfc_type, status, '
      'current_version_id, author_agent, round_count, supersedes, created_at, updated_at';

  // The pgvector `vector` type comes back from the driver as binary; cast it to
  // text (`[1,0,...]`) so DataRowType.toVector() can parse it on read.
  static const _versionColumns =
      'id, rfc_id, version_no, summary, embedding::text AS embedding, embedding_model, '
      'is_latest, supersedes, author_agent, created_at';

  static const _sectionColumns =
      'id, version_id, section_key, content, required, coverage, '
      'embedding::text AS embedding, embedding_model, created_at';

  static const _commentColumns =
      'id, rfc_id, version_id, section_id, author_agent, reviewer_role, type, severity, '
      'area, anchor_quote, problem, rationale, impact, proposed_solution, '
      'alternatives::text AS alternatives, confidence, status, parent_comment_id, verified, '
      'round_no, embedding::text AS embedding, embedding_model, is_latest, supersedes, created_at';

  @override
  Future<RfcEntity> openRfc(
    RfcEntity rfc,
    RfcVersionEntity version,
    List<RfcSectionEntity> sections,
  ) async {
    try {
      final rfcId = rfc.id.isEmpty ? IdVO.generate() : rfc.id;
      final versionId = version.id.isEmpty ? IdVO.generate() : version.id;

      // Header goes in first with a NULL current version (the FK to
      // rfc_versions is satisfied only after the version row exists), and the
      // status is forced to open_for_comments.
      final rfcParams = DatabaseRfcMapper.toInsertParams(rfc)
        ..['id'] = rfcId.value
        ..['status'] = RfcStatus.openForComments.code;

      final versionParams = DatabaseRfcVersionMapper.toInsertParams(
        version.copyWith(rfcId: rfcId, isLatest: true),
      )..['id'] = versionId.value;

      final queries = <SavePointQuery>[
        SavePointQuery(
          statement: SqlStatement(
            'INSERT INTO rfcs '
            '(id, organization_id, project_id, module_id, title, rfc_type, status, '
            'author_agent, round_count, supersedes) '
            'VALUES (:id::uuid, :organization_id::uuid, :project_id::uuid, :module_id::uuid, '
            ':title, :rfc_type, :status, :author_agent, :round_count, :supersedes::uuid) '
            'RETURNING created_at, updated_at',
            rfcParams,
          ),
        ),
        SavePointQuery(
          statement: SqlStatement(
            'INSERT INTO rfc_versions '
            '(id, rfc_id, version_no, summary, embedding, embedding_model, is_latest, '
            'supersedes, author_agent) '
            'VALUES (:id::uuid, :rfc_id::uuid, :version_no, :summary, '
            ':embedding::vector(1024), :embedding_model, :is_latest, :supersedes::uuid, '
            ':author_agent)',
            versionParams,
          ),
        ),
      ];

      for (final section in sections) {
        final params = DatabaseRfcSectionMapper.toInsertParams(
          section.copyWith(versionId: versionId),
        )..['id'] = IdVO.generate().value;
        queries.add(SavePointQuery(
          statement: SqlStatement(
            'INSERT INTO rfc_sections '
            '(id, version_id, section_key, content, required, coverage, embedding, embedding_model) '
            'VALUES (:id::uuid, :version_id::uuid, :section_key, :content, :required, :coverage, '
            ':embedding::vector(1024), :embedding_model)',
            params,
          ),
        ));
      }

      // Close the cycle: point the header at its now-existing current version.
      queries.add(SavePointQuery(
        statement: SqlStatement(
          'UPDATE rfcs SET current_version_id = :vid::uuid, updated_at = now() '
          'WHERE id = :rid::uuid RETURNING updated_at',
          {'vid': versionId.value, 'rid': rfcId.value},
        ),
      ));

      final results = await _database.executeSavePoint(queries);
      final headerRow = results.first.rows.first;
      final updatedRow = results.last.rows.first;
      return rfc.copyWith(
        id: rfcId,
        status: RfcStatus.openForComments,
        currentVersionId: versionId,
        createdAt: headerRow['created_at']?.toDateTime(),
        updatedAt: updatedRow['updated_at']?.toDateTime(),
      );
    } on DatabaseFailure catch (error) {
      throw DatasourceRfcFailure(errorMessage: error.errorMessage, stackTrace: StackTrace.current);
    }
  }

  @override
  Future<RfcBundle> getRfc(IdVO id) async {
    try {
      final rfcResult = await _database.select(
        SqlStatement('SELECT $_rfcColumns FROM rfcs WHERE id = :id::uuid', {'id': id.value}),
      );
      if (rfcResult.rows.isEmpty) {
        throw RfcNotFoundFailure(stackTrace: StackTrace.current);
      }
      final rfc = DatabaseRfcMapper.fromRow(rfcResult.rows.first);

      final versionResult = await _database.select(SqlStatement(
        'SELECT $_versionColumns FROM rfc_versions '
        'WHERE rfc_id = :id::uuid AND is_latest LIMIT 1',
        {'id': id.value},
      ));
      final version = versionResult.rows.isEmpty
          ? null
          : DatabaseRfcVersionMapper.fromRow(versionResult.rows.first);

      var sections = const <RfcSectionEntity>[];
      if (version != null) {
        final sectionResult = await _database.select(SqlStatement(
          'SELECT $_sectionColumns FROM rfc_sections '
          'WHERE version_id = :vid::uuid ORDER BY created_at',
          {'vid': version.id.value},
        ));
        sections = sectionResult.rows.map(DatabaseRfcSectionMapper.fromRow).toList();
      }

      final commentResult = await _database.select(SqlStatement(
        'SELECT $_commentColumns FROM rfc_comments '
        "WHERE rfc_id = :id::uuid AND is_latest AND status = 'open' "
        'ORDER BY created_at',
        {'id': id.value},
      ));
      final comments = commentResult.rows.map(DatabaseRfcCommentMapper.fromRow).toList();

      return RfcBundle(rfc: rfc, version: version, sections: sections, comments: comments);
    } on DatabaseFailure catch (error) {
      throw DatasourceRfcFailure(errorMessage: error.errorMessage, stackTrace: StackTrace.current);
    }
  }

  @override
  Future<List<RfcEntity>> listOpenRfcs({
    IdVO? organizationId,
    IdVO? projectId,
    IdVO? moduleId,
    int? limit,
  }) async {
    try {
      final params = <String, Object?>{'lim': limit ?? 50};
      // Scope union (mirrors memory search): a module listing also surfaces its
      // project's and organization's open RFCs. Most-specific scope first.
      final owners = <String>[];
      if (moduleId != null) {
        owners.add('module_id = :mid::uuid');
        params['mid'] = moduleId.value;
      }
      if (projectId != null) {
        owners.add('project_id = :pid::uuid');
        params['pid'] = projectId.value;
      }
      if (organizationId != null) {
        owners.add('organization_id = :prodid::uuid');
        params['prodid'] = organizationId.value;
      }
      final scope = <String>["status IN ('open_for_comments','in_review')"];
      if (owners.isNotEmpty) scope.add('(${owners.join(' OR ')})');

      final result = await _database.select(SqlStatement(
        'SELECT $_rfcColumns FROM rfcs WHERE ${scope.join(' AND ')} '
        'ORDER BY (module_id IS NOT NULL) DESC, (project_id IS NOT NULL) DESC, '
        'updated_at DESC LIMIT :lim',
        params,
      ));
      return result.rows.map(DatabaseRfcMapper.fromRow).toList();
    } on DatabaseFailure catch (error) {
      throw DatasourceRfcFailure(errorMessage: error.errorMessage, stackTrace: StackTrace.current);
    }
  }

  @override
  Future<RfcCommentEntity> addComment(RfcCommentEntity comment) async {
    try {
      final result = await _database.executeUpdate(SqlStatement(
        'INSERT INTO rfc_comments '
        '(rfc_id, version_id, section_id, author_agent, reviewer_role, type, severity, area, '
        'anchor_quote, problem, rationale, impact, proposed_solution, alternatives, confidence, '
        'status, parent_comment_id, verified, round_no, embedding, embedding_model, supersedes) '
        'VALUES (:rfc_id::uuid, :version_id::uuid, :section_id::uuid, :author_agent, :reviewer_role, '
        ':type, :severity, :area, :anchor_quote, :problem, :rationale, :impact, :proposed_solution, '
        ':alternatives::jsonb, :confidence, :status, :parent_comment_id::uuid, :verified, :round_no, '
        ':embedding::vector(1024), :embedding_model, :supersedes::uuid) '
        'RETURNING id, created_at',
        DatabaseRfcCommentMapper.toInsertParams(comment),
      ));
      final row = result.rows.first;
      return comment.copyWith(
        id: IdVO(row['id']!.toText()!),
        createdAt: row['created_at']?.toDateTime(),
      );
    } on DatabaseFailure catch (error) {
      throw DatasourceRfcFailure(errorMessage: error.errorMessage, stackTrace: StackTrace.current);
    }
  }

  @override
  Future<RfcEvidenceEntity> addEvidence(RfcEvidenceEntity evidence) async {
    try {
      final evidenceId = evidence.id.isEmpty ? IdVO.generate() : evidence.id;

      // Resolve the reference FIRST (reads don't belong in the savepoint): an
      // `oracle_entity` citation counts only if the row it names actually
      // exists. file/external references — and the code/api_contract/test/log/
      // data_model/diagram/business_req kinds — stay unresolved in this pass;
      // excerpt/file validation is a documented follow-up.
      var resolved = false;
      final table = _evidenceRefTable(evidence.kind);
      if (evidence.refKind == 'oracle_entity' && evidence.refId != null && table != null) {
        final existsResult = await _database.select(SqlStatement(
          'SELECT EXISTS(SELECT 1 FROM $table WHERE id = :rid::uuid) AS ok',
          {'rid': evidence.refId!.value},
        ));
        resolved = existsResult.rows.first['ok']?.toBool() ?? false;
      }

      final params = DatabaseRfcEvidenceMapper.toInsertParams(evidence)
        ..['id'] = evidenceId.value
        ..['resolved'] = resolved
        // resolved_at is derived in SQL from :resolved, not passed by the mapper.
        ..remove('resolved_at');

      final queries = <SavePointQuery>[
        SavePointQuery(
          statement: SqlStatement(
            'INSERT INTO rfc_comment_evidence '
            '(id, comment_id, kind, ref_kind, ref_id, locator, excerpt, resolved, resolved_at) '
            'VALUES (:id::uuid, :comment_id::uuid, :kind, :ref_kind, :ref_id::uuid, :locator, '
            ':excerpt, :resolved, CASE WHEN :resolved THEN now() ELSE NULL END) '
            'RETURNING id, created_at, resolved_at',
            params,
          ),
        ),
      ];

      // Verify the comment only when this evidence resolved — never clear a
      // prior verification, since other evidence may already verify it.
      if (resolved) {
        queries.add(SavePointQuery(
          statement: SqlStatement(
            'UPDATE rfc_comments SET verified = true WHERE id = :cid::uuid',
            {'cid': evidence.commentId.value},
          ),
        ));
      }

      final results = await _database.executeSavePoint(queries);
      final row = results.first.rows.first;
      return evidence.copyWith(
        id: IdVO(row['id']!.toText()!),
        resolved: resolved,
        resolvedAt: row['resolved_at']?.toDateTime(),
        createdAt: row['created_at']?.toDateTime(),
      );
    } on DatabaseFailure catch (error) {
      throw DatasourceRfcFailure(errorMessage: error.errorMessage, stackTrace: StackTrace.current);
    }
  }

  /// The table whose existence proves an `oracle_entity` citation of [kind].
  /// Only oracle-entity kinds map; anything else returns null (unresolved).
  static String? _evidenceRefTable(String kind) {
    switch (kind) {
      case 'rule':
        return 'rules';
      case 'memory':
      case 'decision':
        return 'memories';
      case 'architecture':
        return 'architectures';
      case 'prior_rfc':
        return 'rfcs';
      default:
        return null;
    }
  }

  @override
  Future<List<RfcCommentNeighbor>> nearestComments({
    required IdVO rfcId,
    required List<double> embedding,
    required String embeddingModel,
    IdVO? excludeId,
    double? maxDistance,
    int? limit,
  }) async {
    try {
      final params = <String, Object?>{
        'rid': rfcId.value,
        'vec': SqlVector(embedding),
        'model': embeddingModel,
        // Tight default: only surface genuinely near-duplicate findings so the
        // dedup signal stays high-value instead of firing on most comments.
        'maxd': maxDistance ?? 0.12,
        'lim': limit ?? 3,
        'xid': excludeId?.value,
      };
      // Same-model only: cross-model cosine distances are meaningless.
      const sql = 'SELECT $_commentColumns, (embedding <=> :vec::vector(1024)) AS distance '
          'FROM rfc_comments '
          'WHERE is_latest AND embedding IS NOT NULL AND embedding_model = :model '
          'AND rfc_id = :rid::uuid '
          'AND (:xid::uuid IS NULL OR id <> :xid::uuid) '
          'AND (embedding <=> :vec::vector(1024)) < :maxd '
          'ORDER BY distance LIMIT :lim';
      final result = await _database.select(SqlStatement(sql, params));
      return result.rows
          .map((r) => RfcCommentNeighbor(
                comment: DatabaseRfcCommentMapper.fromRow(r),
                distance: r['distance']?.toDouble() ?? 1.0,
              ))
          .toList();
    } on DatabaseFailure catch (error) {
      throw DatasourceRfcFailure(errorMessage: error.errorMessage, stackTrace: StackTrace.current);
    }
  }

  @override
  Future<RfcVersionEntity> reviseRfc(
    RfcVersionEntity version,
    List<RfcSectionEntity> sections,
  ) async {
    try {
      final versionId = version.id.isEmpty ? IdVO.generate() : version.id;
      final rfcId = version.rfcId;

      final versionParams = DatabaseRfcVersionMapper.toInsertParams(
        version.copyWith(isLatest: true),
      )..['id'] = versionId.value;

      final queries = <SavePointQuery>[
        // Retire the prior latest version so the (rfc_id) WHERE is_latest unique
        // index holds when the new version lands.
        SavePointQuery(
          statement: SqlStatement(
            'UPDATE rfc_versions SET is_latest = false '
            'WHERE is_latest AND rfc_id = :rid::uuid',
            {'rid': rfcId.value},
          ),
        ),
        SavePointQuery(
          statement: SqlStatement(
            'INSERT INTO rfc_versions '
            '(id, rfc_id, version_no, summary, embedding, embedding_model, is_latest, '
            'supersedes, author_agent) '
            'VALUES (:id::uuid, :rfc_id::uuid, :version_no, :summary, '
            ':embedding::vector(1024), :embedding_model, :is_latest, :supersedes::uuid, '
            ':author_agent) '
            'RETURNING created_at',
            versionParams,
          ),
        ),
      ];

      for (final section in sections) {
        final params = DatabaseRfcSectionMapper.toInsertParams(
          section.copyWith(versionId: versionId),
        )..['id'] = IdVO.generate().value;
        queries.add(SavePointQuery(
          statement: SqlStatement(
            'INSERT INTO rfc_sections '
            '(id, version_id, section_key, content, required, coverage, embedding, embedding_model) '
            'VALUES (:id::uuid, :version_id::uuid, :section_key, :content, :required, :coverage, '
            ':embedding::vector(1024), :embedding_model)',
            params,
          ),
        ));
      }

      // Bump the round + point the header at the new current version.
      queries.add(SavePointQuery(
        statement: SqlStatement(
          'UPDATE rfcs SET round_count = round_count + 1, current_version_id = :vid::uuid, '
          'updated_at = now() WHERE id = :rid::uuid',
          {'vid': versionId.value, 'rid': rfcId.value},
        ),
      ));

      final results = await _database.executeSavePoint(queries);
      final versionRow = results[1].rows.first;
      return version.copyWith(
        id: versionId,
        isLatest: true,
        createdAt: versionRow['created_at']?.toDateTime(),
      );
    } on DatabaseFailure catch (error) {
      throw DatasourceRfcFailure(errorMessage: error.errorMessage, stackTrace: StackTrace.current);
    }
  }

  @override
  Future<RfcStatusReport> rfcStatus(IdVO rfcId) async {
    try {
      final commentResult = await _database.select(SqlStatement(
        "SELECT "
        "count(*) FILTER (WHERE severity = 'critical' AND status = 'open') AS crit, "
        "count(*) FILTER (WHERE severity = 'critical' AND status = 'open' AND verified) AS blocking_crit, "
        "count(*) FILTER (WHERE severity = 'major' AND status = 'open') AS maj, "
        "count(*) AS total "
        'FROM rfc_comments WHERE rfc_id = :rid::uuid AND is_latest',
        {'rid': rfcId.value},
      ));
      final cRow = commentResult.rows.first;
      final openCriticals = cRow['crit']?.toInt() ?? 0;
      final blockingCriticals = cRow['blocking_crit']?.toInt() ?? 0;
      final openMajors = cRow['maj']?.toInt() ?? 0;
      final totalComments = cRow['total']?.toInt() ?? 0;

      // Coverage is scoped to the RFC's current (latest) version.
      final versionResult = await _database.select(SqlStatement(
        'SELECT id FROM rfc_versions WHERE rfc_id = :rid::uuid AND is_latest LIMIT 1',
        {'rid': rfcId.value},
      ));

      var requiredSections = 0;
      var coveredRequired = 0;
      if (versionResult.rows.isNotEmpty) {
        final versionId = versionResult.rows.first['id']!.toText()!;
        final sectionResult = await _database.select(SqlStatement(
          'SELECT count(*) FILTER (WHERE required) AS req, '
          "count(*) FILTER (WHERE required AND coverage = 'covered') AS covered "
          'FROM rfc_sections WHERE version_id = :vid::uuid',
          {'vid': versionId},
        ));
        final sRow = sectionResult.rows.first;
        requiredSections = sRow['req']?.toInt() ?? 0;
        coveredRequired = sRow['covered']?.toInt() ?? 0;
      }

      return RfcStatusReport(
        openCriticals: openCriticals,
        blockingCriticals: blockingCriticals,
        openMajors: openMajors,
        totalComments: totalComments,
        requiredSections: requiredSections,
        coveredRequired: coveredRequired,
        checklistComplete: requiredSections > 0 && coveredRequired >= requiredSections,
      );
    } on DatabaseFailure catch (error) {
      throw DatasourceRfcFailure(errorMessage: error.errorMessage, stackTrace: StackTrace.current);
    }
  }
}
