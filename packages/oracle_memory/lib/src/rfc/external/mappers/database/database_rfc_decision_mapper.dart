import 'dart:convert';

import 'package:oracle_core/oracle_core.dart';

import '../../../domain/entities/rfc_decision_entity.dart';

/// Maps [RfcDecisionEntity] to/from the `rfc_decisions` table.
class DatabaseRfcDecisionMapper {
  const DatabaseRfcDecisionMapper._();

  /// Params for INSERT. uuids are cast in SQL (`:x::uuid`); `comment_ids` is sent
  /// as JSON text and cast (`:comment_ids::jsonb`).
  static Map<String, Object?> toInsertParams(RfcDecisionEntity d) => {
        'rfc_id': d.rfcId.value,
        'question': d.question.value,
        'chosen_option': d.chosenOption.value,
        'rationale': d.rationale.value,
        'comment_ids': jsonEncode(d.commentIds),
        'human_approved': d.humanApproved,
        'memory_id': d.memoryId?.value,
      };

  static RfcDecisionEntity fromRow(Map<String, DataRowType> row) {
    final memoryId = row['memory_id']?.toText();
    return RfcDecisionEntity(
      id: IdVO(row['id']!.toText()!),
      rfcId: IdVO(row['rfc_id']!.toText()!),
      question: TextVO(row['question']?.toText() ?? ''),
      chosenOption: TextVO(row['chosen_option']?.toText() ?? ''),
      rationale: TextVO(row['rationale']?.toText() ?? ''),
      commentIds: row['comment_ids']?.toStringList() ?? const [],
      humanApproved: row['human_approved']?.toBool() ?? false,
      memoryId: memoryId == null ? null : IdVO(memoryId),
      createdAt: row['created_at']?.toDateTime(),
    );
  }
}
