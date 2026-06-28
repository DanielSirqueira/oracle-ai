import 'package:oracle_core/oracle_core.dart';

import '../../../domain/entities/architecture_entity.dart';

class DatabaseArchitectureMapper {
  const DatabaseArchitectureMapper._();

  static Map<String, Object?> toInsertParams(ArchitectureEntity a) => {
        'project_id': a.projectId.value,
        'area': a.area,
        'content': a.content.value,
        'embedding': a.embedding == null ? null : SqlVector(a.embedding!),
        'embedding_model': a.embeddingModel,
        'supersedes': a.supersedes?.value,
      };

  static ArchitectureEntity fromRow(Map<String, DataRowType> row) {
    final supersedes = row['supersedes']?.toText();
    return ArchitectureEntity(
      id: IdVO(row['id']!.toText()!),
      projectId: IdVO(row['project_id']!.toText()!),
      area: row['area']!.toText() ?? '',
      content: TextVO(row['content']!.toText() ?? ''),
      embedding: row['embedding']?.toVector(),
      embeddingModel: row['embedding_model']?.toText(),
      isLatest: row['is_latest']?.toBool() ?? true,
      supersedes: supersedes == null ? null : IdVO(supersedes),
      createdAt: row['created_at']?.toDateTime(),
      updatedAt: row['updated_at']?.toDateTime(),
    );
  }
}
