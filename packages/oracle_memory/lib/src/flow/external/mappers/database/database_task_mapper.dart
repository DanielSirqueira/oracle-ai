import 'package:oracle_core/oracle_core.dart';

import '../../../domain/entities/task_entity.dart';
import '../../../domain/enums/task_status.dart';

/// Maps [TaskEntity] to/from the `tasks` table.
class DatabaseTaskMapper {
  const DatabaseTaskMapper._();

  static Map<String, Object?> toInsertParams(TaskEntity t) => {
    'organization_id': t.organizationId?.value,
    'project_id': t.projectId?.value,
    'module_id': t.moduleId?.value,
    'title': t.title.value,
    'description': t.description,
    'status': t.status.code,
    'priority': t.priority,
    'source': t.source,
    'rfc_id': t.rfcId?.value,
    'created_by': t.createdBy,
    'embedding': t.embedding == null ? null : SqlVector(t.embedding!),
    'embedding_model': t.embeddingModel,
  };

  static TaskEntity fromRow(Map<String, DataRowType> row) {
    final organizationId = row['organization_id']?.toText();
    final projectId = row['project_id']?.toText();
    final moduleId = row['module_id']?.toText();
    final rfcId = row['rfc_id']?.toText();
    return TaskEntity(
      id: IdVO(row['id']!.toText()!),
      organizationId: organizationId == null ? null : IdVO(organizationId),
      projectId: projectId == null ? null : IdVO(projectId),
      moduleId: moduleId == null ? null : IdVO(moduleId),
      title: TextVO(row['title']!.toText() ?? ''),
      description: row['description']?.toText() ?? '',
      status: TaskStatus.parse(row['status']!.toText() ?? 'backlog'),
      priority: row['priority']?.toInt() ?? 50,
      source: row['source']?.toText() ?? 'human',
      rfcId: rfcId == null ? null : IdVO(rfcId),
      createdBy: row['created_by']?.toText() ?? 'human',
      embedding: row['embedding']?.toVector(),
      embeddingModel: row['embedding_model']?.toText(),
      createdAt: row['created_at']?.toDateTime(),
      updatedAt: row['updated_at']?.toDateTime(),
    );
  }
}
