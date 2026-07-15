import 'package:oracle_core/oracle_core.dart';

import '../../../domain/entities/rfc_round_entity.dart';

/// Maps [RfcRoundEntity] to/from the `rfc_rounds` table.
class DatabaseRfcRoundMapper {
  const DatabaseRfcRoundMapper._();

  /// Params for INSERT. uuids are cast in SQL (`:x::uuid`); `participants` is a
  /// `text[]` sent as a plain list param (`:participants`).
  static Map<String, Object?> toInsertParams(RfcRoundEntity r) => {
        'rfc_id': r.rfcId.value,
        'version_id': r.versionId?.value,
        'round_no': r.roundNo,
        'participants': r.participants,
        'new_criticals': r.newCriticals,
        'new_majors': r.newMajors,
        'novelty_score': r.noveltyScore,
      };

  static RfcRoundEntity fromRow(Map<String, DataRowType> row) {
    final versionId = row['version_id']?.toText();
    return RfcRoundEntity(
      id: IdVO(row['id']!.toText()!),
      rfcId: IdVO(row['rfc_id']!.toText()!),
      versionId: versionId == null ? null : IdVO(versionId),
      roundNo: row['round_no']?.toInt() ?? 0,
      participants: row['participants']?.toStringList() ?? const [],
      newCriticals: row['new_criticals']?.toInt() ?? 0,
      newMajors: row['new_majors']?.toInt() ?? 0,
      noveltyScore: row['novelty_score']?.toDouble(),
      startedAt: row['started_at']?.toDateTime(),
      endedAt: row['ended_at']?.toDateTime(),
    );
  }
}
