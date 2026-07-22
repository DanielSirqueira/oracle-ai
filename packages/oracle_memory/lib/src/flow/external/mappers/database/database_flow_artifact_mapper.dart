import 'package:oracle_core/oracle_core.dart';

import '../../../domain/entities/flow_artifact_entity.dart';

/// Maps [FlowArtifactEntity] to/from the `flow_artifacts` table.
class DatabaseFlowArtifactMapper {
  const DatabaseFlowArtifactMapper._();

  static Map<String, Object?> toInsertParams(FlowArtifactEntity a) => {
    'run_id': a.runId.value,
    'run_step_id': a.runStepId?.value,
    'kind': a.kind,
    'locator': a.locator,
    'meta': a.meta,
  };

  static FlowArtifactEntity fromRow(Map<String, DataRowType> row) {
    final runStepId = row['run_step_id']?.toText();
    return FlowArtifactEntity(
      id: IdVO(row['id']!.toText()!),
      runId: IdVO(row['run_id']!.toText()!),
      runStepId: runStepId == null ? null : IdVO(runStepId),
      kind: row['kind']?.toText() ?? 'other',
      locator: row['locator']?.toText() ?? '',
      meta: row['meta']?.toText() ?? '{}',
      createdAt: row['created_at']?.toDateTime(),
    );
  }
}
