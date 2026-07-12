import 'package:oracle_core/oracle_core.dart';

import '../../../domain/entities/module_entity.dart';

/// Maps [ModuleEntity] to/from the `modules` table.
class DatabaseModuleMapper {
  const DatabaseModuleMapper._();

  static const columns =
      'id, project_id, key, name, path, description, created_at, updated_at';

  static Map<String, Object?> toInsertParams(ModuleEntity m) => {
        'project_id': m.projectId.value,
        'key': m.key,
        'name': m.name.value,
        'path': m.path,
        'description': m.description?.value,
      };

  static ModuleEntity fromRow(Map<String, DataRowType> row) {
    final description = row['description']?.toText();
    return ModuleEntity(
      id: IdVO(row['id']!.toText()!),
      projectId: IdVO(row['project_id']!.toText()!),
      key: row['key']!.toText() ?? '',
      name: TextVO(row['name']!.toText() ?? ''),
      path: row['path']?.toText(),
      description: description == null ? null : TextVO(description),
      createdAt: row['created_at']?.toDateTime(),
      updatedAt: row['updated_at']?.toDateTime(),
    );
  }
}
