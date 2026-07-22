import 'package:oracle_core/oracle_core.dart';

import '../../../domain/entities/flow_run_context_entity.dart';

/// Maps [FlowRunContextEntity] to/from the `flow_run_context` table.
class DatabaseFlowRunContextMapper {
  const DatabaseFlowRunContextMapper._();

  static Map<String, Object?> toInsertParams(FlowRunContextEntity c) => {
    'run_id': c.runId.value,
    'key': c.key,
    'value': c.value,
    'updated_by': c.updatedBy?.value,
  };

  static FlowRunContextEntity fromRow(Map<String, DataRowType> row) {
    final updatedBy = row['updated_by']?.toText();
    return FlowRunContextEntity(
      runId: IdVO(row['run_id']!.toText()!),
      key: row['key']?.toText() ?? '',
      value: row['value']?.toText() ?? '{}',
      updatedBy: updatedBy == null ? null : IdVO(updatedBy),
      updatedAt: row['updated_at']?.toDateTime(),
    );
  }
}
