import 'package:oracle_core/oracle_core.dart';

import '../../../domain/entities/flow_entity.dart';

/// Maps [FlowEntity] to/from the `flows` table.
class DatabaseFlowMapper {
  const DatabaseFlowMapper._();

  static Map<String, Object?> toInsertParams(FlowEntity f) => {
    'organization_id': f.organizationId?.value,
    'project_id': f.projectId?.value,
    'module_id': f.moduleId?.value,
    'key': f.key,
    'name': f.name.value,
    'description': f.description,
    'orchestrator_agent': f.orchestratorAgent,
    'entry_step_key': f.entryStepKey,
    'budgets': f.budgets,
    'version_no': f.versionNo,
    'is_latest': f.isLatest,
    'supersedes': f.supersedes?.value,
  };

  static FlowEntity fromRow(Map<String, DataRowType> row) {
    final organizationId = row['organization_id']?.toText();
    final projectId = row['project_id']?.toText();
    final moduleId = row['module_id']?.toText();
    final supersedes = row['supersedes']?.toText();
    return FlowEntity(
      id: IdVO(row['id']!.toText()!),
      organizationId: organizationId == null ? null : IdVO(organizationId),
      projectId: projectId == null ? null : IdVO(projectId),
      moduleId: moduleId == null ? null : IdVO(moduleId),
      key: row['key']?.toText() ?? '',
      name: TextVO(row['name']?.toText() ?? ''),
      description: row['description']?.toText() ?? '',
      orchestratorAgent: row['orchestrator_agent']?.toText() ?? 'claude-code',
      entryStepKey: row['entry_step_key']?.toText() ?? '',
      budgets: row['budgets']?.toText() ?? '{}',
      versionNo: row['version_no']?.toInt() ?? 1,
      isLatest: row['is_latest']?.toBool() ?? true,
      supersedes: supersedes == null ? null : IdVO(supersedes),
      retiredAt: row['retired_at']?.toDateTime(),
      retiredReason: row['retired_reason']?.toText(),
      createdAt: row['created_at']?.toDateTime(),
      updatedAt: row['updated_at']?.toDateTime(),
    );
  }
}
