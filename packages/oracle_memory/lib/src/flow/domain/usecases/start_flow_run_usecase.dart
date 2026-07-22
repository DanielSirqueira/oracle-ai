import 'dart:convert';

import 'package:oracle_core/oracle_core.dart';

import '../dtos/flow_graph.dart';
import '../entities/flow_run_entity.dart';
import '../enums/task_status.dart';
import '../errors/flow_failure.dart';
import '../repositories/flow_repository.dart';

/// Enqueues a run of a flow for a task (status `queued`). Resolves the flow by id
/// or by key + scope, pins its version, and derives the run's project scope from
/// the task (or the flow). The Flow Runner executes it.
abstract interface class StartFlowRunUsecase {
  AsyncResultDart<FlowRunEntity, FlowFailure> call({
    IdVO? taskId,
    IdVO? flowId,
    String? flowKey,
    IdVO? organizationId,
    IdVO? projectId,
    IdVO? moduleId,
    String? budgets,
    String startedBy = 'human',
  });
}

class StartFlowRunUsecaseImpl implements StartFlowRunUsecase {
  final FlowRepository _repository;
  const StartFlowRunUsecaseImpl(this._repository);

  @override
  AsyncResultDart<FlowRunEntity, FlowFailure> call({
    IdVO? taskId,
    IdVO? flowId,
    String? flowKey,
    IdVO? organizationId,
    IdVO? projectId,
    IdVO? moduleId,
    String? budgets,
    String startedBy = 'human',
  }) async {
    final ResultDart<FlowGraph, FlowFailure> graphResult;
    if (flowId != null && flowId.isNotEmpty) {
      graphResult = await _repository.getFlow(flowId);
    } else if (flowKey != null && flowKey.isNotEmpty) {
      graphResult = await _repository.getFlowByKey(
        organizationId: organizationId,
        projectId: projectId,
        moduleId: moduleId,
        key: flowKey,
      );
    } else {
      return Failure(
        ValidatedFieldFlowFailure(
          errorMessage: 'flowId or flowKey required',
          stackTrace: StackTrace.current,
          fields: const [
            FieldSystemFailure(
              field: 'flow',
              message: 'flowId or flowKey required',
            ),
          ],
        ),
      );
    }
    if (graphResult.isError()) return Failure(graphResult.exceptionOrNull()!);
    final graph = graphResult.getOrThrow();

    final effectiveBudgets = (budgets != null && budgets.isNotEmpty)
        ? budgets
        : graph.flow.budgets;
    try {
      final decoded = jsonDecode(effectiveBudgets);
      if (decoded is! Map) throw const FormatException('not an object');
      for (final key in const ['maxTotalTokens', 'maxWallMinutes']) {
        final value = decoded[key];
        if (value != null && (value is! num || value < 0)) {
          throw FormatException('$key must be non-negative');
        }
      }
    } catch (error) {
      return Failure(
        ValidatedFieldFlowFailure(
          errorMessage: 'Invalid run budgets',
          stackTrace: StackTrace.current,
          fields: [FieldSystemFailure(field: 'budgets', message: '$error')],
        ),
      );
    }

    var runProjectId = projectId ?? graph.flow.projectId;
    if (taskId != null && taskId.isNotEmpty) {
      final taskResult = await _repository.getTask(taskId);
      if (taskResult.isError()) return Failure(taskResult.exceptionOrNull()!);
      final task = taskResult.getOrThrow();
      runProjectId = runProjectId ?? task.projectId;
      if (task.status == TaskStatus.done ||
          task.status == TaskStatus.cancelled) {
        return Failure(
          ValidatedFieldFlowFailure(
            errorMessage:
                'Completed or cancelled tasks cannot be executed again. Create a new task.',
            stackTrace: StackTrace.current,
            fields: const [
              FieldSystemFailure(
                field: 'taskId',
                message: 'The task lifecycle is terminal',
              ),
            ],
          ),
        );
      }
      if (task.status == TaskStatus.running) {
        return Failure(
          ValidatedFieldFlowFailure(
            errorMessage: 'This task already has an execution in progress.',
            stackTrace: StackTrace.current,
            fields: const [
              FieldSystemFailure(
                field: 'taskId',
                message: 'The task is already running',
              ),
            ],
          ),
        );
      }
    }
    if (runProjectId == null || runProjectId.isEmpty) {
      return Failure(
        ValidatedFieldFlowFailure(
          errorMessage: 'A project is required to run a development process.',
          stackTrace: StackTrace.current,
          fields: const [
            FieldSystemFailure(
              field: 'projectId',
              message: 'Agent sessions require a project',
            ),
          ],
        ),
      );
    }

    final run = FlowRunEntity(
      id: const IdVO.empty(),
      flowId: graph.flow.id,
      taskId: taskId,
      projectId: runProjectId,
      budgets: effectiveBudgets,
      startedBy: startedBy,
    );
    final started = await _repository.startRun(run);
    return started;
  }
}
