import 'package:oracle_core/oracle_core.dart';

import '../../../domain/entities/rfc_version_entity.dart';

/// Maps [RfcVersionEntity] to/from the `rfc_versions` table.
class DatabaseRfcVersionMapper {
  const DatabaseRfcVersionMapper._();

  /// Params for INSERT. uuids are cast in SQL (`:x::uuid`); the embedding is
  /// sent via [SqlVector] and cast (`:embedding::vector(1024)`).
  static Map<String, Object?> toInsertParams(RfcVersionEntity v) => {
        'rfc_id': v.rfcId.value,
        'version_no': v.versionNo,
        'summary': v.summary.value,
        'embedding': v.embedding == null ? null : SqlVector(v.embedding!),
        'embedding_model': v.embeddingModel,
        'is_latest': v.isLatest,
        'supersedes': v.supersedes?.value,
        'author_agent': v.authorAgent,
      };

  static RfcVersionEntity fromRow(Map<String, DataRowType> row) {
    final supersedes = row['supersedes']?.toText();
    return RfcVersionEntity(
      id: IdVO(row['id']!.toText()!),
      rfcId: IdVO(row['rfc_id']!.toText()!),
      versionNo: row['version_no']?.toInt() ?? 1,
      summary: TextVO(row['summary']!.toText() ?? ''),
      embedding: row['embedding']?.toVector(),
      embeddingModel: row['embedding_model']?.toText(),
      isLatest: row['is_latest']?.toBool() ?? true,
      supersedes: supersedes == null ? null : IdVO(supersedes),
      authorAgent: row['author_agent']?.toText() ?? 'claude-code',
      createdAt: row['created_at']?.toDateTime(),
    );
  }
}
