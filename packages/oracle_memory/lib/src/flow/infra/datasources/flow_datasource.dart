import 'package:oracle_core/oracle_core.dart';

import '../../domain/dtos/flow_graph.dart';
import '../../domain/dtos/flow_run_bundle.dart';
import '../../domain/dtos/step_context.dart';
import '../../domain/dtos/task_neighbor.dart';
import '../../domain/entities/flow_artifact_entity.dart';
import '../../domain/entities/flow_edge_entity.dart';
import '../../domain/entities/flow_entity.dart';
import '../../domain/entities/flow_run_context_entity.dart';
import '../../domain/entities/flow_run_entity.dart';
import '../../domain/entities/flow_run_event_entity.dart';
import '../../domain/entities/flow_run_step_entity.dart';
import '../../domain/entities/flow_step_entity.dart';
import '../../domain/entities/task_entity.dart';
import '../../domain/enums/flow_run_status.dart';
import '../../domain/enums/task_status.dart';

/// Data-access contract for Loop Engineering (tasks + flows + runs).
/// Implementations **throw** typed failures; the repository wraps them in a
/// `ResultDart`.
abstract interface class FlowDatasource {
  // ── tasks ──────────────────────────────────────────────────────────────
  Future<TaskEntity> createTask(TaskEntity task);
  Future<TaskEntity> getTask(IdVO id);
  Future<List<TaskEntity>> listTasks({
    IdVO? organizationId,
    IdVO? projectId,
    IdVO? moduleId,
    String? status,
    String? search,
    int? limit,
  });
  Future<TaskEntity> updateTask(
    IdVO id, {
    TaskStatus? status,
    int? priority,
    String? description,
  });

  /// Latest tasks within [maxDistance] cosine distance of [embedding] (same model
  /// only). Backs the "asked before?" dedup signal; empty when nothing is close.
  Future<List<TaskNeighbor>> nearestTasks({
    IdVO? organizationId,
    IdVO? projectId,
    IdVO? moduleId,
    required List<double> embedding,
    required String embeddingModel,
    IdVO? excludeId,
    double? maxDistance,
    int? limit,
  });

  // ── flows (definition) ─────────────────────────────────────────────────
  /// Saves the whole graph (flow + steps + edges) in one savepoint. Re-saving the
  /// same key in the same scope supersedes the prior latest.
  Future<FlowGraph> saveFlow(
    FlowEntity flow,
    List<FlowStepEntity> steps,
    List<FlowEdgeEntity> edges,
  );
  Future<FlowGraph> getFlow(IdVO id);
  Future<FlowGraph?> getFlowByKey({
    IdVO? organizationId,
    IdVO? projectId,
    IdVO? moduleId,
    required String key,
  });
  Future<List<FlowEntity>> listFlows({
    IdVO? organizationId,
    IdVO? projectId,
    IdVO? moduleId,
    int? limit,
  });

  // ── runs (execution) ───────────────────────────────────────────────────
  /// Enqueues a run (status `queued`). The worker executes it.
  Future<FlowRunEntity> startRun(FlowRunEntity run);
  Future<FlowRunBundle> getRun(IdVO id);
  Future<List<FlowRunEntity>> listRuns({
    IdVO? projectId,
    String? status,
    int? limit,
  });

  /// Atomically claims the oldest queued run (FOR UPDATE SKIP LOCKED), marks it
  /// `running` + stamps the lease. Returns null when the queue is empty.
  Future<FlowRunEntity?> claimRun(String workerId);
  Future<FlowRunEntity?> claimChildRun(IdVO id, String workerId);
  Future<bool> heartbeatRun(IdVO id, String workerId, int leaseEpoch);
  Future<bool> checkpointRun(
    IdVO id,
    String workerId,
    int leaseEpoch, {
    String? executionState,
    IdVO? currentStepId,
    bool clearCurrentStep = false,
    String? branchName,
    String? worktreePath,
    int addTokens = 0,
  });
  Future<FlowRunEntity> updateRunStatus(
    IdVO id,
    FlowRunStatus status, {
    IdVO? currentStepId,
    String? error,
    String? branchName,
    String? worktreePath,
    int addTokens = 0,
    String? expectedWorkerId,
    int? expectedLeaseEpoch,
    Set<FlowRunStatus>? expectedStatuses,
  });

  // ── run steps (the inner loop) ─────────────────────────────────────────
  Future<FlowRunStepEntity> startRunStep(FlowRunStepEntity runStep);
  Future<FlowRunStepEntity> updateRunStep(FlowRunStepEntity runStep);
  Future<FlowRunStepEntity> getRunStep(IdVO id);

  /// The bundle a step's agent pulls: task, run, step, blackboard context, prior
  /// reports and artifacts.
  Future<StepContext> stepContext(IdVO runStepId);

  /// Resolves the Oracle session id captured for [externalId] (the agent's own
  /// session id), scoped to [projectId] when known. Null when no session row
  /// exists yet (the hooks capture is asynchronous).
  Future<IdVO?> resolveSessionId({IdVO? projectId, required String externalId});

  // ── blackboard / artifacts / timeline ──────────────────────────────────
  /// Upserts a blackboard entry (on run_id + key).
  Future<FlowRunContextEntity> putContext(FlowRunContextEntity ctx);
  Future<FlowArtifactEntity> addArtifact(FlowArtifactEntity artifact);
  Future<FlowRunEventEntity> addEvent(FlowRunEventEntity event);
}
