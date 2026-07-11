import 'package:oracle_core/oracle_core.dart';

import '../../../domain/entities/project_entity.dart';

/// Maps [ProjectEntity] to/from the `projects` table.
class DatabaseProjectMapper {
  const DatabaseProjectMapper._();

  /// Params for INSERT/UPDATE. `organization_id` is sent as text and cast to `uuid`
  /// in the SQL (`:organization_id::uuid`).
  static Map<String, Object?> toInsertParams(ProjectEntity project) => {
        'organization_id': project.organizationId?.value,
        'name': project.name.value,
        'description': project.description?.value,
        'repo_path': project.repoPath,
      };

  /// Builds a [ProjectEntity] from a result row.
  static ProjectEntity fromRow(Map<String, DataRowType> row) {
    final organizationId = row['organization_id']?.toText();
    final description = row['description']?.toText();
    return ProjectEntity(
      id: IdVO(row['id']!.toText()!),
      organizationId: organizationId == null ? null : IdVO(organizationId),
      name: TextVO(row['name']!.toText() ?? ''),
      description: description == null ? null : TextVO(description),
      repoPath: row['repo_path']?.toText(),
      createdAt: row['created_at']?.toDateTime(),
      updatedAt: row['updated_at']?.toDateTime(),
    );
  }
}
