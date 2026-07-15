import 'dart:convert';

import 'package:oracle_core/oracle_core.dart';

import '../../../domain/entities/rfc_comment_entity.dart';
import '../../../domain/enums/rfc_comment_type.dart';
import '../../../domain/enums/rfc_severity.dart';

/// Maps [RfcCommentEntity] to/from the `rfc_comments` table.
class DatabaseRfcCommentMapper {
  const DatabaseRfcCommentMapper._();

  /// Params for INSERT. uuids are cast in SQL (`:x::uuid`); the embedding is
  /// sent via [SqlVector] and cast (`:embedding::vector(1024)`); `alternatives`
  /// is sent as JSON text and cast (`:alternatives::jsonb`).
  static Map<String, Object?> toInsertParams(RfcCommentEntity c) => {
        'rfc_id': c.rfcId.value,
        'version_id': c.versionId.value,
        'section_id': c.sectionId?.value,
        'author_agent': c.authorAgent,
        'reviewer_role': c.reviewerRole,
        'type': c.type.code,
        'severity': c.severity.code,
        'area': c.area,
        'anchor_quote': c.anchorQuote,
        'problem': c.problem.value,
        'rationale': c.rationale.value,
        'impact': c.impact.value,
        'proposed_solution': c.proposedSolution.value,
        'alternatives': jsonEncode(c.alternatives),
        'confidence': c.confidence,
        'status': c.status,
        'parent_comment_id': c.parentCommentId?.value,
        'verified': c.verified,
        'round_no': c.roundNo,
        'embedding': c.embedding == null ? null : SqlVector(c.embedding!),
        'embedding_model': c.embeddingModel,
        'supersedes': c.supersedes?.value,
      };

  static RfcCommentEntity fromRow(Map<String, DataRowType> row) {
    List<Map<String, dynamic>> arr(String? s) => (s == null || s.isEmpty)
        ? const []
        : (jsonDecode(s) as List).cast<Map<String, dynamic>>();
    final sectionId = row['section_id']?.toText();
    final parentCommentId = row['parent_comment_id']?.toText();
    final supersedes = row['supersedes']?.toText();
    return RfcCommentEntity(
      id: IdVO(row['id']!.toText()!),
      rfcId: IdVO(row['rfc_id']!.toText()!),
      versionId: IdVO(row['version_id']!.toText()!),
      sectionId: sectionId == null ? null : IdVO(sectionId),
      authorAgent: row['author_agent']?.toText() ?? 'claude-code',
      reviewerRole: row['reviewer_role']?.toText(),
      type: RfcCommentType.parse(row['type']!.toText() ?? 'improvement'),
      severity: RfcSeverity.parse(row['severity']!.toText() ?? 'info'),
      area: row['area']?.toText(),
      anchorQuote: row['anchor_quote']?.toText(),
      problem: TextVO(row['problem']!.toText() ?? ''),
      rationale: TextVO(row['rationale']!.toText() ?? ''),
      impact: TextVO(row['impact']!.toText() ?? ''),
      proposedSolution: TextVO(row['proposed_solution']!.toText() ?? ''),
      alternatives: arr(row['alternatives']?.toText()),
      confidence: row['confidence']?.toDouble() ?? 0.5,
      status: row['status']?.toText() ?? 'open',
      parentCommentId: parentCommentId == null ? null : IdVO(parentCommentId),
      verified: row['verified']?.toBool() ?? false,
      roundNo: row['round_no']?.toInt() ?? 0,
      embedding: row['embedding']?.toVector(),
      embeddingModel: row['embedding_model']?.toText(),
      isLatest: row['is_latest']?.toBool() ?? true,
      supersedes: supersedes == null ? null : IdVO(supersedes),
      createdAt: row['created_at']?.toDateTime(),
    );
  }
}
