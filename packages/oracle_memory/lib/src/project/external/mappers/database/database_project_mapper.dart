import 'package:oracle_core/oracle_core.dart';

import '../../../domain/entities/project_entity.dart';

/// Maps [ProjectEntity] to/from the `projects` table.
class DatabaseProjectMapper {
  const DatabaseProjectMapper._();

  /// Params for INSERT/UPDATE. `product_id` is sent as text and cast to `uuid`
  /// in the SQL (`:product_id::uuid`).
  static Map<String, Object?> toInsertParams(ProjectEntity project) => {
        'product_id': project.productId?.value,
        'name': project.name.value,
        'description': project.description?.value,
        'repo_path': project.repoPath,
      };

  /// Builds a [ProjectEntity] from a result row.
  static ProjectEntity fromRow(Map<String, DataRowType> row) {
    final productId = row['product_id']?.toText();
    final description = row['description']?.toText();
    return ProjectEntity(
      id: IdVO(row['id']!.toText()!),
      productId: productId == null ? null : IdVO(productId),
      name: TextVO(row['name']!.toText() ?? ''),
      description: description == null ? null : TextVO(description),
      repoPath: row['repo_path']?.toText(),
      createdAt: row['created_at']?.toDateTime(),
      updatedAt: row['updated_at']?.toDateTime(),
    );
  }
}
