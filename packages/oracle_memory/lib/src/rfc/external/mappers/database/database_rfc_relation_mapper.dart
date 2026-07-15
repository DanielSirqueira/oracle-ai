import 'dart:convert';

import 'package:oracle_core/oracle_core.dart';

import '../../../domain/entities/rfc_relation_entity.dart';

/// Maps [RfcRelationEntity] to/from the `rfc_comment_relations` table.
class DatabaseRfcRelationMapper {
  const DatabaseRfcRelationMapper._();

  /// Params for INSERT. uuids are cast in SQL (`:x::uuid`); `evidence` is sent as
  /// JSON text and cast (`:evidence::jsonb`).
  static Map<String, Object?> toInsertParams(RfcRelationEntity r) => {
        'from_comment': r.fromComment.value,
        'to_comment': r.toComment.value,
        'relation': r.relation,
        'ground': r.ground,
        'reason': r.reason.value,
        'evidence': jsonEncode(r.evidence),
      };

  static RfcRelationEntity fromRow(Map<String, DataRowType> row) {
    List<Map<String, dynamic>> arr(String? s) => (s == null || s.isEmpty)
        ? const []
        : (jsonDecode(s) as List).cast<Map<String, dynamic>>();
    return RfcRelationEntity(
      id: IdVO(row['id']!.toText()!),
      fromComment: IdVO(row['from_comment']!.toText()!),
      toComment: IdVO(row['to_comment']!.toText()!),
      relation: row['relation']?.toText() ?? '',
      ground: row['ground']?.toText(),
      reason: TextVO(row['reason']?.toText() ?? ''),
      evidence: arr(row['evidence']?.toText()),
      createdAt: row['created_at']?.toDateTime(),
    );
  }
}
