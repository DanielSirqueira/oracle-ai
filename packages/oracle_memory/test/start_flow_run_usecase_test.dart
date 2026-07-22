import 'package:oracle_core/oracle_core.dart';
import 'package:oracle_memory/oracle_memory.dart';
import 'package:test/test.dart';

const _projectId = IdVO('00000000-0000-4000-8000-000000000001');
const _taskId = IdVO('00000000-0000-4000-8000-000000000002');
const _flowId = IdVO('00000000-0000-4000-8000-000000000003');

void main() {
  group('StartFlowRunUsecase lifecycle guard', () {
    test('rejects a completed task without creating another run', () async {
      final repository = _FlowRepositoryFake(taskStatus: TaskStatus.done);
      final result = await StartFlowRunUsecaseImpl(repository)(
        taskId: _taskId,
        flowId: _flowId,
        projectId: _projectId,
      );

      expect(result.isError(), isTrue);
      expect(
        result.exceptionOrNull()!.errorMessage,
        contains('cannot be executed again'),
      );
      expect(repository.startedRuns, 0);
    });

    test('rejects a task that already has an execution in progress', () async {
      final repository = _FlowRepositoryFake(taskStatus: TaskStatus.running);
      final result = await StartFlowRunUsecaseImpl(repository)(
        taskId: _taskId,
        flowId: _flowId,
        projectId: _projectId,
      );

      expect(result.isError(), isTrue);
      expect(repository.startedRuns, 0);
    });

    test('starts an eligible task once', () async {
      final repository = _FlowRepositoryFake(taskStatus: TaskStatus.ready);
      final result = await StartFlowRunUsecaseImpl(repository)(
        taskId: _taskId,
        flowId: _flowId,
        projectId: _projectId,
      );

      expect(result.isSuccess(), isTrue);
      expect(repository.startedRuns, 1);
    });

    test('requires project scope so every agent can own a session', () async {
      final repository = _FlowRepositoryFake(
        taskStatus: TaskStatus.ready,
        taskProjectId: null,
        flowProjectId: null,
      );
      final result = await StartFlowRunUsecaseImpl(repository)(
        taskId: _taskId,
        flowId: _flowId,
      );

      expect(result.isError(), isTrue);
      expect(
        result.exceptionOrNull()!.errorMessage,
        contains('project is required'),
      );
      expect(repository.startedRuns, 0);
    });
  });
}

class _FlowRepositoryFake implements FlowRepository {
  final TaskStatus taskStatus;
  final IdVO? taskProjectId;
  final IdVO? flowProjectId;
  int startedRuns = 0;

  _FlowRepositoryFake({
    required this.taskStatus,
    this.taskProjectId = _projectId,
    this.flowProjectId = _projectId,
  });

  @override
  AsyncResultDart<FlowGraph, FlowFailure> getFlow(IdVO id) async => Success(
    FlowGraph(
      flow: FlowEntity(
        id: _flowId,
        projectId: flowProjectId,
        key: 'development',
        name: const TextVO('Development'),
      ),
    ),
  );

  @override
  AsyncResultDart<TaskEntity, FlowFailure> getTask(IdVO id) async => Success(
    TaskEntity(
      id: _taskId,
      projectId: taskProjectId,
      title: const TextVO('Build feature'),
      status: taskStatus,
    ),
  );

  @override
  AsyncResultDart<FlowRunEntity, FlowFailure> startRun(
    FlowRunEntity run,
  ) async {
    startedRuns++;
    return Success(
      run.copyWith(id: const IdVO('00000000-0000-4000-8000-000000000004')),
    );
  }

  @override
  AsyncResultDart<TaskEntity, FlowFailure> updateTask(
    IdVO id, {
    TaskStatus? status,
    int? priority,
    String? description,
  }) async {
    return Success(
      TaskEntity(
        id: _taskId,
        projectId: taskProjectId,
        title: const TextVO('Build feature'),
        status: status ?? taskStatus,
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
