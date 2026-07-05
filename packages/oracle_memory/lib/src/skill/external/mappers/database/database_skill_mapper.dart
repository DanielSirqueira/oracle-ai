import 'package:oracle_core/oracle_core.dart';

import '../../../domain/entities/skill_entity.dart';

/// Maps [SkillEntity] to/from the `skills` table.
class DatabaseSkillMapper {
  const DatabaseSkillMapper._();

  static Map<String, Object?> toInsertParams(SkillEntity s) => {
        'product_id': s.productId?.value,
        'project_id': s.projectId?.value,
        'key': s.key,
        'name': s.name.value,
        'description': s.description.value,
        'content': s.content.value,
        'tags': s.tags,
        'embedding': s.embedding == null ? null : SqlVector(s.embedding!),
        'embedding_model': s.embeddingModel,
        'supersedes': s.supersedes?.value,
      };

  static SkillEntity fromRow(Map<String, DataRowType> row) {
    final productId = row['product_id']?.toText();
    final projectId = row['project_id']?.toText();
    final supersedes = row['supersedes']?.toText();
    return SkillEntity(
      id: IdVO(row['id']!.toText()!),
      productId: productId == null ? null : IdVO(productId),
      projectId: projectId == null ? null : IdVO(projectId),
      key: row['key']!.toText() ?? '',
      name: TextVO(row['name']!.toText() ?? ''),
      description: TextVO(row['description']!.toText() ?? ''),
      content: TextVO(row['content']!.toText() ?? ''),
      tags: row['tags']?.toStringList() ?? const [],
      embedding: row['embedding']?.toVector(),
      embeddingModel: row['embedding_model']?.toText(),
      isLatest: row['is_latest']?.toBool() ?? true,
      supersedes: supersedes == null ? null : IdVO(supersedes),
      createdAt: row['created_at']?.toDateTime(),
      updatedAt: row['updated_at']?.toDateTime(),
    );
  }
}
