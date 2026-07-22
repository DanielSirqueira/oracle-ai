import 'package:oracle_core/oracle_core.dart';

import '../enums/flow_run_status.dart';

/// A running instance of a flow for a task. Pins the flow version. The worker
/// claims it with [claimedBy] + [heartbeatAt] (a lease); all run state lives in
/// the database, so an orphaned run (stale heartbeat) is resumable from the last
/// event. [tokensUsed] is summed from the steps' captured sessions.
class FlowRunEntity {
  final IdVO id;
  final IdVO flowId;
  final IdVO? taskId;
  final IdVO? projectId;
  final FlowRunStatus status;
  final IdVO? currentStepId;
  final String? branchName;
  final String? worktreePath;
  final String budgets;
  final int tokensUsed;
  final String startedBy;
  final String? claimedBy;
  final DateTime? heartbeatAt;
  final String? error;
  final String executionState;
  final int leaseEpoch;
  final IdVO? parentRunId;
  final DateTime? createdAt;
  final DateTime? startedAt;
  final DateTime? endedAt;

  const FlowRunEntity({
    required this.id,
    required this.flowId,
    this.taskId,
    this.projectId,
    this.status = FlowRunStatus.queued,
    this.currentStepId,
    this.branchName,
    this.worktreePath,
    this.budgets = '{}',
    this.tokensUsed = 0,
    this.startedBy = 'human',
    this.claimedBy,
    this.heartbeatAt,
    this.error,
    this.executionState = '{}',
    this.leaseEpoch = 0,
    this.parentRunId,
    this.createdAt,
    this.startedAt,
    this.endedAt,
  });

  FlowRunEntity copyWith({
    IdVO? id,
    IdVO? flowId,
    IdVO? taskId,
    IdVO? projectId,
    FlowRunStatus? status,
    IdVO? currentStepId,
    String? branchName,
    String? worktreePath,
    String? budgets,
    int? tokensUsed,
    String? startedBy,
    String? claimedBy,
    DateTime? heartbeatAt,
    String? error,
    String? executionState,
    int? leaseEpoch,
    IdVO? parentRunId,
    DateTime? createdAt,
    DateTime? startedAt,
    DateTime? endedAt,
  }) {
    return FlowRunEntity(
      id: id ?? this.id,
      flowId: flowId ?? this.flowId,
      taskId: taskId ?? this.taskId,
      projectId: projectId ?? this.projectId,
      status: status ?? this.status,
      currentStepId: currentStepId ?? this.currentStepId,
      branchName: branchName ?? this.branchName,
      worktreePath: worktreePath ?? this.worktreePath,
      budgets: budgets ?? this.budgets,
      tokensUsed: tokensUsed ?? this.tokensUsed,
      startedBy: startedBy ?? this.startedBy,
      claimedBy: claimedBy ?? this.claimedBy,
      heartbeatAt: heartbeatAt ?? this.heartbeatAt,
      error: error ?? this.error,
      executionState: executionState ?? this.executionState,
      leaseEpoch: leaseEpoch ?? this.leaseEpoch,
      parentRunId: parentRunId ?? this.parentRunId,
      createdAt: createdAt ?? this.createdAt,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FlowRunEntity &&
        other.id == id &&
        other.flowId == flowId &&
        other.taskId == taskId &&
        other.projectId == projectId &&
        other.status == status &&
        other.currentStepId == currentStepId &&
        other.branchName == branchName &&
        other.worktreePath == worktreePath &&
        other.budgets == budgets &&
        other.tokensUsed == tokensUsed &&
        other.startedBy == startedBy &&
        other.claimedBy == claimedBy &&
        other.executionState == executionState &&
        other.leaseEpoch == leaseEpoch &&
        other.parentRunId == parentRunId;
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    flowId,
    taskId,
    projectId,
    status,
    currentStepId,
    branchName,
    worktreePath,
    budgets,
    tokensUsed,
    startedBy,
    claimedBy,
    executionState,
    leaseEpoch,
    parentRunId,
  ]);
}
