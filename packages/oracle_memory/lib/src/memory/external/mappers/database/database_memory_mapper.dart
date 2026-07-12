import 'package:oracle_core/oracle_core.dart';

import '../../../domain/entities/memory_entity.dart';
import '../../../domain/enums/memory_kind.dart';
import '../../../domain/enums/memory_tier.dart';

/// Maps [MemoryEntity] to/from the `memories` table.
class DatabaseMemoryMapper {
  const DatabaseMemoryMapper._();

  /// Params for INSERT. uuids are cast in SQL (`:x::uuid`); the embedding is
  /// sent via [SqlVector] and cast (`:embedding::vector(1024)`).
  static Map<String, Object?> toInsertParams(MemoryEntity m) => {
        'organization_id': m.organizationId?.value,
        'project_id': m.projectId?.value,
        'module_id': m.moduleId?.value,
        'key': m.key,
        'tier': m.tier.code,
        'kind': m.kind.code,
        'title': m.title.value,
        'body': m.body.value,
        'tags': m.tags,
        'importance': m.importance,
        'embedding': m.embedding == null ? null : SqlVector(m.embedding!),
        'embedding_model': m.embeddingModel,
        'supersedes': m.supersedes?.value,
      };

  static MemoryEntity fromRow(Map<String, DataRowType> row) {
    final organizationId = row['organization_id']?.toText();
    final projectId = row['project_id']?.toText();
    final moduleId = row['module_id']?.toText();
    final supersedes = row['supersedes']?.toText();
    return MemoryEntity(
      id: IdVO(row['id']!.toText()!),
      organizationId: organizationId == null ? null : IdVO(organizationId),
      projectId: projectId == null ? null : IdVO(projectId),
      moduleId: moduleId == null ? null : IdVO(moduleId),
      key: row['key']?.toText(),
      tier: MemoryTier.parse(row['tier']!.toText() ?? 'semantic'),
      kind: MemoryKind.parse(row['kind']!.toText() ?? 'fact'),
      title: TextVO(row['title']!.toText() ?? ''),
      body: TextVO(row['body']!.toText() ?? ''),
      tags: row['tags']?.toStringList() ?? const [],
      importance: row['importance']?.toDouble() ?? 0,
      embedding: row['embedding']?.toVector(),
      embeddingModel: row['embedding_model']?.toText(),
      isLatest: row['is_latest']?.toBool() ?? true,
      supersedes: supersedes == null ? null : IdVO(supersedes),
      createdAt: row['created_at']?.toDateTime(),
      updatedAt: row['updated_at']?.toDateTime(),
    );
  }
}
