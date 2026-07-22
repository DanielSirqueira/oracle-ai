import 'package:oracle_core/oracle_core.dart';

import '../../../domain/entities/flow_run_event_entity.dart';

/// Maps [FlowRunEventEntity] to/from the `flow_run_events` table.
class DatabaseFlowRunEventMapper {
  const DatabaseFlowRunEventMapper._();

  static Map<String, Object?> toInsertParams(FlowRunEventEntity e) => {
    'run_id': e.runId.value,
    'run_step_id': e.runStepId?.value,
    'kind': e.kind,
    'payload': e.payload,
  };

  static FlowRunEventEntity fromRow(Map<String, DataRowType> row) {
    final runStepId = row['run_step_id']?.toText();
    return FlowRunEventEntity(
      id: IdVO(row['id']!.toText()!),
      runId: IdVO(row['run_id']!.toText()!),
      runStepId: runStepId == null ? null : IdVO(runStepId),
      kind: row['kind']?.toText() ?? 'info',
      payload: row['payload']?.toText() ?? '{}',
      createdAt: row['created_at']?.toDateTime(),
    );
  }
}
