import 'package:oracle_core/oracle_core.dart';

import '../../../domain/entities/skill_entity.dart';

/// Maps [SkillEntity] to/from the `skills` table.
class DatabaseSkillMapper {
  const DatabaseSkillMapper._();

  static Map<String, Object?> toInsertParams(SkillEntity s) => {
        'organization_id': s.organizationId?.value,
        'project_id': s.projectId?.value,
        'module_id': s.moduleId?.value,
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
    final organizationId = row['organization_id']?.toText();
    final projectId = row['project_id']?.toText();
    final moduleId = row['module_id']?.toText();
    final supersedes = row['supersedes']?.toText();
    return SkillEntity(
      id: IdVO(row['id']!.toText()!),
      organizationId: organizationId == null ? null : IdVO(organizationId),
      projectId: projectId == null ? null : IdVO(projectId),
      moduleId: moduleId == null ? null : IdVO(moduleId),
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
