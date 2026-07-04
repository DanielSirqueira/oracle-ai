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
        'product_id': m.productId?.value,
        'project_id': m.projectId?.value,
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
    final productId = row['product_id']?.toText();
    final projectId = row['project_id']?.toText();
    final supersedes = row['supersedes']?.toText();
    return MemoryEntity(
      id: IdVO(row['id']!.toText()!),
      productId: productId == null ? null : IdVO(productId),
      projectId: projectId == null ? null : IdVO(projectId),
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
