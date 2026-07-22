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
import '../../domain/errors/flow_failure.dart';
import '../../domain/repositories/flow_repository.dart';
import '../datasources/flow_datasource.dart';

/// Wraps [FlowDatasource] calls in a `ResultDart`, catching typed failures.
class FlowRepositoryImpl implements FlowRepository {
  final FlowDatasource _datasource;
  const FlowRepositoryImpl({required FlowDatasource datasource})
    : _datasource = datasource;

  @override
  AsyncResultDart<TaskEntity, FlowFailure> createTask(TaskEntity task) async {
    try {
      return Success(await _datasource.createTask(task));
    } on FlowFailure catch (failure) {
      return Failure(failure);
    }
  }

  @override
  AsyncResultDart<TaskEntity, FlowFailure> getTask(IdVO id) async {
    try {
      return Success(await _datasource.getTask(id));
    } on FlowFailure catch (failure) {
      return Failure(failure);
    }
  }

  @override
  AsyncResultDart<List<TaskEntity>, FlowFailure> listTasks({
    IdVO? organizationId,
    IdVO? projectId,
    IdVO? moduleId,
    String? status,
    String? search,
    int? limit,
  }) async {
    try {
      return Success(
        await _datasource.listTasks(
          organizationId: organizationId,
          projectId: projectId,
          moduleId: moduleId,
          status: status,
          search: search,
          limit: limit,
        ),
      );
    } on FlowFailure catch (failure) {
      return Failure(failure);
    }
  }

  @override
  AsyncResultDart<TaskEntity, FlowFailure> updateTask(
    IdVO id, {
    TaskStatus? status,
    int? priority,
    String? description,
  }) async {
    try {
      return Success(
        await _datasource.updateTask(
          id,
          status: status,
          priority: priority,
          description: description,
        ),
      );
    } on FlowFailure catch (failure) {
      return Failure(failure);
    }
  }

  @override
  Future<List<TaskNeighbor>> nearestTasks({
    IdVO? organizationId,
    IdVO? projectId,
    IdVO? moduleId,
    required List<double> embedding,
    required String embeddingModel,
    IdVO? excludeId,
    double? maxDistance,
    int? limit,
  }) async {
    try {
      return await _datasource.nearestTasks(
        organizationId: organizationId,
        projectId: projectId,
        moduleId: moduleId,
        embedding: embedding,
        embeddingModel: embeddingModel,
        excludeId: excludeId,
        maxDistance: maxDistance,
        limit: limit,
      );
    } on FlowFailure {
      return const [];
    }
  }

  @override
  AsyncResultDart<FlowGraph, FlowFailure> saveFlow(
    FlowEntity flow,
    List<FlowStepEntity> steps,
    List<FlowEdgeEntity> edges,
  ) async {
    try {
      return Success(await _datasource.saveFlow(flow, steps, edges));
    } on FlowFailure catch (failure) {
      return Failure(failure);
    }
  }

  @override
  AsyncResultDart<FlowGraph, FlowFailure> getFlow(IdVO id) async {
    try {
      return Success(await _datasource.getFlow(id));
    } on FlowFailure catch (failure) {
      return Failure(failure);
    }
  }

  @override
  AsyncResultDart<FlowGraph, FlowFailure> getFlowByKey({
    IdVO? organizationId,
    IdVO? projectId,
    IdVO? moduleId,
    required String key,
  }) async {
    try {
      final graph = await _datasource.getFlowByKey(
        organizationId: organizationId,
        projectId: projectId,
        moduleId: moduleId,
        key: key,
      );
      if (graph == null) {
        return Failure(FlowNotFoundFailure(stackTrace: StackTrace.current));
      }
      return Success(graph);
    } on FlowFailure catch (failure) {
      return Failure(failure);
    }
  }

  @override
  AsyncResultDart<List<FlowEntity>, FlowFailure> listFlows({
    IdVO? organizationId,
    IdVO? projectId,
    IdVO? moduleId,
    int? limit,
  }) async {
    try {
      return Success(
        await _datasource.listFlows(
          organizationId: organizationId,
          projectId: projectId,
          moduleId: moduleId,
          limit: limit,
        ),
      );
    } on FlowFailure catch (failure) {
      return Failure(failure);
    }
  }

  @override
  AsyncResultDart<FlowRunEntity, FlowFailure> startRun(
    FlowRunEntity run,
  ) async {
    try {
      return Success(await _datasource.startRun(run));
    } on FlowFailure catch (failure) {
      return Failure(failure);
    }
  }

  @override
  AsyncResultDart<FlowRunBundle, FlowFailure> getRun(IdVO id) async {
    try {
      return Success(await _datasource.getRun(id));
    } on FlowFailure catch (failure) {
      return Failure(failure);
    }
  }

  @override
  AsyncResultDart<List<FlowRunEntity>, FlowFailure> listRuns({
    IdVO? projectId,
    String? status,
    int? limit,
  }) async {
    try {
      return Success(
        await _datasource.listRuns(
          projectId: projectId,
          status: status,
          limit: limit,
        ),
      );
    } on FlowFailure catch (failure) {
      return Failure(failure);
    }
  }

  @override
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
  }) async {
    try {
      return Success(
        await _datasource.updateRunStatus(
          id,
          status,
          currentStepId: currentStepId,
          error: error,
          branchName: branchName,
          worktreePath: worktreePath,
          addTokens: addTokens,
          expectedWorkerId: expectedWorkerId,
          expectedLeaseEpoch: expectedLeaseEpoch,
          expectedStatuses: expectedStatuses,
        ),
      );
    } on FlowFailure catch (failure) {
      return Failure(failure);
    }
  }

  @override
  Future<FlowRunEntity?> claimRun(String workerId) async {
    try {
      return await _datasource.claimRun(workerId);
    } on FlowFailure {
      return null;
    }
  }

  @override
  Future<FlowRunEntity?> claimChildRun(IdVO id, String workerId) async {
    try {
      return await _datasource.claimChildRun(id, workerId);
    } on FlowFailure {
      return null;
    }
  }

  @override
  Future<bool> heartbeatRun(IdVO id, String workerId, int leaseEpoch) async {
    try {
      return await _datasource.heartbeatRun(id, workerId, leaseEpoch);
    } on FlowFailure {
      return false;
    }
  }

  @override
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
  }) async {
    try {
      return await _datasource.checkpointRun(
        id,
        workerId,
        leaseEpoch,
        executionState: executionState,
        currentStepId: currentStepId,
        clearCurrentStep: clearCurrentStep,
        branchName: branchName,
        worktreePath: worktreePath,
        addTokens: addTokens,
      );
    } on FlowFailure {
      return false;
    }
  }

  @override
  AsyncResultDart<FlowRunStepEntity, FlowFailure> getRunStep(IdVO id) async {
    try {
      return Success(await _datasource.getRunStep(id));
    } on FlowFailure catch (failure) {
      return Failure(failure);
    }
  }

  @override
  AsyncResultDart<FlowRunStepEntity, FlowFailure> startRunStep(
    FlowRunStepEntity runStep,
  ) async {
    try {
      return Success(await _datasource.startRunStep(runStep));
    } on FlowFailure catch (failure) {
      return Failure(failure);
    }
  }

  @override
  AsyncResultDart<FlowRunStepEntity, FlowFailure> updateRunStep(
    FlowRunStepEntity runStep,
  ) async {
    try {
      return Success(await _datasource.updateRunStep(runStep));
    } on FlowFailure catch (failure) {
      return Failure(failure);
    }
  }

  @override
  AsyncResultDart<StepContext, FlowFailure> stepContext(IdVO runStepId) async {
    try {
      return Success(await _datasource.stepContext(runStepId));
    } on FlowFailure catch (failure) {
      return Failure(failure);
    }
  }

  @override
  Future<IdVO?> resolveSessionId({
    IdVO? projectId,
    required String externalId,
  }) async {
    try {
      return await _datasource.resolveSessionId(
        projectId: projectId,
        externalId: externalId,
      );
    } on FlowFailure {
      return null;
    }
  }

  @override
  AsyncResultDart<FlowRunContextEntity, FlowFailure> putContext(
    FlowRunContextEntity ctx,
  ) async {
    try {
      return Success(await _datasource.putContext(ctx));
    } on FlowFailure catch (failure) {
      return Failure(failure);
    }
  }

  @override
  AsyncResultDart<FlowArtifactEntity, FlowFailure> addArtifact(
    FlowArtifactEntity artifact,
  ) async {
    try {
      return Success(await _datasource.addArtifact(artifact));
    } on FlowFailure catch (failure) {
      return Failure(failure);
    }
  }

  @override
  AsyncResultDart<FlowRunEventEntity, FlowFailure> addEvent(
    FlowRunEventEntity event,
  ) async {
    try {
      return Success(await _datasource.addEvent(event));
    } on FlowFailure catch (failure) {
      return Failure(failure);
    }
  }
}
