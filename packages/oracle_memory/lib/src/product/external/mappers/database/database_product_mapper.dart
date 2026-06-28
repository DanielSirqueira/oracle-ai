import 'package:oracle_core/oracle_core.dart';

import '../../../domain/entities/product_entity.dart';

class DatabaseProductMapper {
  const DatabaseProductMapper._();

  static Map<String, Object?> toInsertParams(ProductEntity p) => {
        'name': p.name.value,
        'description': p.description?.value,
      };

  static ProductEntity fromRow(Map<String, DataRowType> row) {
    final description = row['description']?.toText();
    return ProductEntity(
      id: IdVO(row['id']!.toText()!),
      name: TextVO(row['name']!.toText() ?? ''),
      description: description == null ? null : TextVO(description),
      createdAt: row['created_at']?.toDateTime(),
      updatedAt: row['updated_at']?.toDateTime(),
    );
  }
}
