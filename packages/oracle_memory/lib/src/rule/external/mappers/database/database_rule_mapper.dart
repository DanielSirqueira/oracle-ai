import 'package:oracle_core/oracle_core.dart';

import '../../../domain/entities/rule_entity.dart';
import '../../../domain/enums/rule_severity.dart';

/// Maps [RuleEntity] to/from the `rules` table.
class DatabaseRuleMapper {
  const DatabaseRuleMapper._();

  static Map<String, Object?> toInsertParams(RuleEntity r) => {
        'organization_id': r.organizationId?.value,
        'project_id': r.projectId?.value,
        'key': r.key,
        'scope': r.scope,
        'title': r.title.value,
        'content': r.content.value,
        'severity': r.severity.code,
        'priority': r.priority,
        'tags': r.tags,
        'embedding': r.embedding == null ? null : SqlVector(r.embedding!),
        'embedding_model': r.embeddingModel,
        'supersedes': r.supersedes?.value,
      };

  static RuleEntity fromRow(Map<String, DataRowType> row) {
    final organizationId = row['organization_id']?.toText();
    final projectId = row['project_id']?.toText();
    final supersedes = row['supersedes']?.toText();
    return RuleEntity(
      id: IdVO(row['id']!.toText()!),
      organizationId: organizationId == null ? null : IdVO(organizationId),
      projectId: projectId == null ? null : IdVO(projectId),
      key: row['key']!.toText() ?? '',
      scope: row['scope']!.toText() ?? '',
      title: TextVO(row['title']!.toText() ?? ''),
      content: TextVO(row['content']!.toText() ?? ''),
      severity: RuleSeverity.parse(row['severity']!.toText() ?? 'recommended'),
      priority: row['priority']?.toInt() ?? 50,
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
