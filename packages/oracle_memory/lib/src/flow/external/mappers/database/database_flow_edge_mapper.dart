import 'package:oracle_core/oracle_core.dart';

import '../../../domain/entities/flow_edge_entity.dart';

/// Maps [FlowEdgeEntity] to/from the `flow_edges` table.
class DatabaseFlowEdgeMapper {
  const DatabaseFlowEdgeMapper._();

  static Map<String, Object?> toInsertParams(FlowEdgeEntity e) => {
    'flow_id': e.flowId.value,
    'from_step': e.fromStep.value,
    'to_step': e.toStep.value,
    'condition': e.condition,
    'verdict_value': e.verdictValue,
    'instruction': e.instruction,
  };

  static FlowEdgeEntity fromRow(Map<String, DataRowType> row) {
    return FlowEdgeEntity(
      id: IdVO(row['id']!.toText()!),
      flowId: IdVO(row['flow_id']!.toText()!),
      fromStep: IdVO(row['from_step']!.toText()!),
      toStep: IdVO(row['to_step']!.toText()!),
      condition: row['condition']?.toText() ?? 'success',
      verdictValue: row['verdict_value']?.toText(),
      instruction: row['instruction']?.toText(),
      createdAt: row['created_at']?.toDateTime(),
    );
  }
}
