import 'package:oracle_core/oracle_core.dart';

import '../../../domain/entities/rfc_resolution_entity.dart';

/// Maps [RfcResolutionEntity] to/from the `rfc_comment_resolutions` table.
class DatabaseRfcResolutionMapper {
  const DatabaseRfcResolutionMapper._();

  /// Params for INSERT. uuids are cast in SQL (`:x::uuid`).
  static Map<String, Object?> toInsertParams(RfcResolutionEntity r) => {
        'comment_id': r.commentId.value,
        'resolver_agent': r.resolverAgent,
        'decision': r.decision,
        'ground': r.ground,
        'reason': r.reason.value,
        'rule_id': r.ruleId?.value,
      };

  static RfcResolutionEntity fromRow(Map<String, DataRowType> row) {
    final ruleId = row['rule_id']?.toText();
    return RfcResolutionEntity(
      id: IdVO(row['id']!.toText()!),
      commentId: IdVO(row['comment_id']!.toText()!),
      resolverAgent: row['resolver_agent']?.toText() ?? 'claude-code',
      decision: row['decision']?.toText() ?? '',
      ground: row['ground']?.toText(),
      reason: TextVO(row['reason']?.toText() ?? ''),
      ruleId: ruleId == null ? null : IdVO(ruleId),
      decidedAt: row['decided_at']?.toDateTime(),
    );
  }
}
