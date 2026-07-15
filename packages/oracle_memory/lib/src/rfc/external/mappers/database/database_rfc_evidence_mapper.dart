import 'package:oracle_core/oracle_core.dart';

import '../../../domain/entities/rfc_evidence_entity.dart';

/// Maps [RfcEvidenceEntity] to/from the `rfc_comment_evidence` table.
class DatabaseRfcEvidenceMapper {
  const DatabaseRfcEvidenceMapper._();

  /// Params for INSERT. uuids are cast in SQL (`:x::uuid`).
  static Map<String, Object?> toInsertParams(RfcEvidenceEntity e) => {
        'comment_id': e.commentId.value,
        'kind': e.kind,
        'ref_kind': e.refKind,
        'ref_id': e.refId?.value,
        'locator': e.locator,
        'excerpt': e.excerpt,
        'resolved': e.resolved,
        'resolved_at': e.resolvedAt,
      };

  static RfcEvidenceEntity fromRow(Map<String, DataRowType> row) {
    final refId = row['ref_id']?.toText();
    return RfcEvidenceEntity(
      id: IdVO(row['id']!.toText()!),
      commentId: IdVO(row['comment_id']!.toText()!),
      kind: row['kind']?.toText() ?? '',
      refKind: row['ref_kind']?.toText() ?? 'oracle_entity',
      refId: refId == null ? null : IdVO(refId),
      locator: row['locator']?.toText(),
      excerpt: row['excerpt']?.toText(),
      resolved: row['resolved']?.toBool() ?? false,
      resolvedAt: row['resolved_at']?.toDateTime(),
      createdAt: row['created_at']?.toDateTime(),
    );
  }
}
