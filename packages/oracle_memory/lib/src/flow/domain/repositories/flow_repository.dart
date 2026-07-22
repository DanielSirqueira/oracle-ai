import 'package:oracle_core/oracle_core.dart';

import '../dtos/flow_graph.dart';
import '../dtos/flow_run_bundle.dart';
import '../dtos/step_context.dart';
import '../dtos/task_neighbor.dart';
import '../entities/flow_artifact_entity.dart';
import '../entities/flow_edge_entity.dart';
import '../entities/flow_entity.dart';
import '../entities/flow_run_context_entity.dart';
import '../entities/flow_run_entity.dart';
import '../entities/flow_run_event_entity.dart';
import '../entities/flow_run_step_entity.dart';
import '../entities/flow_step_entity.dart';
import '../entities/task_entity.dart';
import '../enums/flow_run_status.dart';
import '../enums/task_status.dart';
import '../errors/flow_failure.dart';

/// Business contract for Loop Engineering. Critical operations return a
/// `ResultDart`; the near-duplicate lookup degrades to an empty list instead of
/// surfacing a failure.
abstract interface class FlowRepository {
  // ── tasks ──
  AsyncResultDart<TaskEntity, FlowFailure> createTask(TaskEntity task);
  AsyncResultDart<TaskEntity, FlowFailure> getTask(IdVO id);
  AsyncResultDart<List<TaskEntity>, FlowFailure> listTasks({
    IdVO? organizationId,
    IdVO? projectId,
    IdVO? moduleId,
    String? status,
    String? search,
    int? limit,
  });
  AsyncResultDart<TaskEntity, FlowFailure> updateTask(
    IdVO id, {
    TaskStatus? status,
    int? priority,
    String? description,
  });
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

  // ── flows ──
  AsyncResultDart<FlowGraph, FlowFailure> saveFlow(
    FlowEntity flow,
    List<FlowStepEntity> steps,
    List<FlowEdgeEntity> edges,
  );
  AsyncResultDart<FlowGraph, FlowFailure> getFlow(IdVO id);
  AsyncResultDart<FlowGraph, FlowFailure> getFlowByKey({
    IdVO? organizationId,
    IdVO? projectId,
    IdVO? moduleId,
    required String key,
  });
  AsyncResultDart<List<FlowEntity>, FlowFailure> listFlows({
    IdVO? organizationId,
    IdVO? projectId,
    IdVO? moduleId,
    int? limit,
  });

  // ── runs ──
  AsyncResultDart<FlowRunEntity, FlowFailure> startRun(FlowRunEntity run);
  AsyncResultDart<FlowRunBundle, FlowFailure> getRun(IdVO id);
  AsyncResultDart<List<FlowRunEntity>, FlowFailure> listRuns({
    IdVO? projectId,
    String? status,
    int? limit,
  });
  AsyncResultDart<FlowRunEntity, FlowFailure> updateRunStatus(
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

  /// Claims the oldest queued run for [workerId]; null-success when empty.
  Future<FlowRunEntity?> claimRun(String workerId);
  Future<FlowRunEntity?> claimChildRun(IdVO id, String workerId);
  Future<bool> heartbeatRun(IdVO id, String workerId, int leaseEpoch);

  /// Persists the scheduler frontier without changing the lifecycle status.
  /// Returns false when the lease was lost or the run is no longer running.
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

  // ── run steps ──
  AsyncResultDart<FlowRunStepEntity, FlowFailure> getRunStep(IdVO id);
  AsyncResultDart<FlowRunStepEntity, FlowFailure> startRunStep(
    FlowRunStepEntity runStep,
  );
  AsyncResultDart<FlowRunStepEntity, FlowFailure> updateRunStep(
    FlowRunStepEntity runStep,
  );
  AsyncResultDart<StepContext, FlowFailure> stepContext(IdVO runStepId);

  /// Best-effort resolution of the captured session id for the agent's own
  /// [externalId]; null when unresolved (never surfaces a failure).
  Future<IdVO?> resolveSessionId({IdVO? projectId, required String externalId});

  // ── blackboard / artifacts / timeline ──
  AsyncResultDart<FlowRunContextEntity, FlowFailure> putContext(
    FlowRunContextEntity ctx,
  );
  AsyncResultDart<FlowArtifactEntity, FlowFailure> addArtifact(
    FlowArtifactEntity artifact,
  );
  AsyncResultDart<FlowRunEventEntity, FlowFailure> addEvent(
    FlowRunEventEntity event,
  );
}
