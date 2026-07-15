import 'package:oracle_core/oracle_core.dart';

import '../../../domain/entities/rfc_entity.dart';
import '../../../domain/enums/rfc_status.dart';

/// Maps [RfcEntity] to/from the `rfcs` table.
class DatabaseRfcMapper {
  const DatabaseRfcMapper._();

  /// Params for INSERT. uuids are cast in SQL (`:x::uuid`).
  static Map<String, Object?> toInsertParams(RfcEntity r) => {
        'organization_id': r.organizationId?.value,
        'project_id': r.projectId?.value,
        'module_id': r.moduleId?.value,
        'title': r.title.value,
        'rfc_type': r.rfcType,
        'status': r.status.code,
        'author_agent': r.authorAgent,
        'round_count': r.roundCount,
        'supersedes': r.supersedes?.value,
      };

  static RfcEntity fromRow(Map<String, DataRowType> row) {
    final organizationId = row['organization_id']?.toText();
    final projectId = row['project_id']?.toText();
    final moduleId = row['module_id']?.toText();
    final currentVersionId = row['current_version_id']?.toText();
    final supersedes = row['supersedes']?.toText();
    return RfcEntity(
      id: IdVO(row['id']!.toText()!),
      organizationId: organizationId == null ? null : IdVO(organizationId),
      projectId: projectId == null ? null : IdVO(projectId),
      moduleId: moduleId == null ? null : IdVO(moduleId),
      title: TextVO(row['title']!.toText() ?? ''),
      rfcType: row['rfc_type']?.toText() ?? 'generic',
      status: RfcStatus.parse(row['status']!.toText() ?? 'draft'),
      currentVersionId: currentVersionId == null ? null : IdVO(currentVersionId),
      authorAgent: row['author_agent']?.toText() ?? 'claude-code',
      roundCount: row['round_count']?.toInt() ?? 0,
      supersedes: supersedes == null ? null : IdVO(supersedes),
      createdAt: row['created_at']?.toDateTime(),
      updatedAt: row['updated_at']?.toDateTime(),
    );
  }
}
