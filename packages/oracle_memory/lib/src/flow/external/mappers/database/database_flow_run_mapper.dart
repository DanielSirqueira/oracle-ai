import 'package:oracle_core/oracle_core.dart';

import '../../../domain/entities/flow_run_entity.dart';
import '../../../domain/enums/flow_run_status.dart';

/// Maps [FlowRunEntity] to/from the `flow_runs` table.
class DatabaseFlowRunMapper {
  const DatabaseFlowRunMapper._();

  static Map<String, Object?> toInsertParams(FlowRunEntity r) => {
    'flow_id': r.flowId.value,
    'task_id': r.taskId?.value,
    'project_id': r.projectId?.value,
    'status': r.status.code,
    'budgets': r.budgets,
    'started_by': r.startedBy,
    'execution_state': r.executionState,
    'parent_run_id': r.parentRunId?.value,
    'claimed_by': r.claimedBy,
    'lease_epoch': r.leaseEpoch,
  };

  static FlowRunEntity fromRow(Map<String, DataRowType> row) {
    final taskId = row['task_id']?.toText();
    final projectId = row['project_id']?.toText();
    final currentStepId = row['current_step_id']?.toText();
    final parentRunId = row['parent_run_id']?.toText();
    return FlowRunEntity(
      id: IdVO(row['id']!.toText()!),
      flowId: IdVO(row['flow_id']!.toText()!),
      taskId: taskId == null ? null : IdVO(taskId),
      projectId: projectId == null ? null : IdVO(projectId),
      status: FlowRunStatus.parse(row['status']!.toText() ?? 'queued'),
      currentStepId: currentStepId == null ? null : IdVO(currentStepId),
      branchName: row['branch_name']?.toText(),
      worktreePath: row['worktree_path']?.toText(),
      budgets: row['budgets']?.toText() ?? '{}',
      tokensUsed: row['tokens_used']?.toInt() ?? 0,
      startedBy: row['started_by']?.toText() ?? 'human',
      claimedBy: row['claimed_by']?.toText(),
      heartbeatAt: row['heartbeat_at']?.toDateTime(),
      error: row['error']?.toText(),
      executionState: row['execution_state']?.toText() ?? '{}',
      leaseEpoch: row['lease_epoch']?.toInt() ?? 0,
      parentRunId: parentRunId == null ? null : IdVO(parentRunId),
      createdAt: row['created_at']?.toDateTime(),
      startedAt: row['started_at']?.toDateTime(),
      endedAt: row['ended_at']?.toDateTime(),
    );
  }
}
