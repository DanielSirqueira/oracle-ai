import 'package:oracle_core/oracle_core.dart';

import '../../../domain/entities/rfc_section_entity.dart';

/// Maps [RfcSectionEntity] to/from the `rfc_sections` table.
class DatabaseRfcSectionMapper {
  const DatabaseRfcSectionMapper._();

  /// Params for INSERT. uuids are cast in SQL (`:x::uuid`); the embedding is
  /// sent via [SqlVector] and cast (`:embedding::vector(1024)`).
  static Map<String, Object?> toInsertParams(RfcSectionEntity s) => {
        'version_id': s.versionId.value,
        'section_key': s.sectionKey,
        'content': s.content.value,
        'required': s.required,
        'coverage': s.coverage,
        'embedding': s.embedding == null ? null : SqlVector(s.embedding!),
        'embedding_model': s.embeddingModel,
      };

  static RfcSectionEntity fromRow(Map<String, DataRowType> row) {
    return RfcSectionEntity(
      id: IdVO(row['id']!.toText()!),
      versionId: IdVO(row['version_id']!.toText()!),
      sectionKey: row['section_key']?.toText() ?? '',
      content: TextVO(row['content']!.toText() ?? ''),
      required: row['required']?.toBool() ?? false,
      coverage: row['coverage']?.toText() ?? 'missing',
      embedding: row['embedding']?.toVector(),
      embeddingModel: row['embedding_model']?.toText(),
      createdAt: row['created_at']?.toDateTime(),
    );
  }
}
