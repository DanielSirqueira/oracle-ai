import 'package:oracle_core/oracle_core.dart';

import '../../../domain/entities/organization_entity.dart';

class DatabaseOrganizationMapper {
  const DatabaseOrganizationMapper._();

  static Map<String, Object?> toInsertParams(OrganizationEntity p) => {
        'name': p.name.value,
        'description': p.description?.value,
      };

  static OrganizationEntity fromRow(Map<String, DataRowType> row) {
    final description = row['description']?.toText();
    return OrganizationEntity(
      id: IdVO(row['id']!.toText()!),
      name: TextVO(row['name']!.toText() ?? ''),
      description: description == null ? null : TextVO(description),
      createdAt: row['created_at']?.toDateTime(),
      updatedAt: row['updated_at']?.toDateTime(),
    );
  }
}
