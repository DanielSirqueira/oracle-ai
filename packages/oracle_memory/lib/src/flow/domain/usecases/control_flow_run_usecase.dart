import 'dart:convert';

import 'package:oracle_core/oracle_core.dart';

import '../entities/flow_run_entity.dart';
import '../entities/flow_run_event_entity.dart';
import '../enums/flow_run_status.dart';
import '../enums/task_status.dart';
import '../errors/flow_failure.dart';
import '../repositories/flow_repository.dart';

/// Pauses, resumes or cancels a run, and records the control action on the
/// timeline. `pause → paused`, `cancel → cancelled`, and `resume → queued` —
/// re-enqueued so a worker RE-CLAIMS and continues driving it (the pausing
/// worker released the run at the pause boundary; plain `running` would leave
/// it orphaned with no driver).
abstract interface class ControlFlowRunUsecase {
  AsyncResultDart<FlowRunEntity, FlowFailure> call(IdVO runId, String action);
}

class ControlFlowRunUsecaseImpl implements ControlFlowRunUsecase {
  final FlowRepository _repository;
  const ControlFlowRunUsecaseImpl(this._repository);

  @override
  AsyncResultDart<FlowRunEntity, FlowFailure> call(
    IdVO runId,
    String action,
  ) async {
    final status = switch (action) {
      'pause' => FlowRunStatus.paused,
      'resume' => FlowRunStatus.queued,
      'cancel' => FlowRunStatus.cancelled,
      _ => null,
    };
    if (status == null) {
      return Failure(
        ValidatedFieldFlowFailure(
          errorMessage: 'Unknown action',
          stackTrace: StackTrace.current,
          fields: const [
            FieldSystemFailure(
              field: 'action',
              message: 'pause | resume | cancel',
            ),
          ],
        ),
      );
    }
    final currentResult = await _repository.getRun(runId);
    if (currentResult.isError()) {
      return Failure(currentResult.exceptionOrNull()!);
    }
    final current = currentResult.getOrThrow().run;
    final allowed = switch (action) {
      'pause' => const {FlowRunStatus.queued, FlowRunStatus.running},
      'resume' => const {FlowRunStatus.paused, FlowRunStatus.stalled},
      'cancel' => const {
        FlowRunStatus.queued,
        FlowRunStatus.running,
        FlowRunStatus.paused,
        FlowRunStatus.awaitingHuman,
        FlowRunStatus.stalled,
      },
      _ => const <FlowRunStatus>{},
    };
    if (!allowed.contains(current.status)) {
      return Failure(
        ValidatedFieldFlowFailure(
          errorMessage: 'Cannot $action a run in ${current.status.code} status',
          stackTrace: StackTrace.current,
          fields: [
            FieldSystemFailure(
              field: 'action',
              message: 'Allowed from: ${allowed.map((e) => e.code).join(', ')}',
            ),
          ],
        ),
      );
    }
    final result = await _repository.updateRunStatus(
      runId,
      status,
      expectedStatuses: allowed,
    );
    if (result.isError()) return result;

    if (current.taskId != null) {
      await _repository.updateTask(
        current.taskId!,
        status: switch (action) {
          'resume' => TaskStatus.ready,
          'cancel' => TaskStatus.cancelled,
          _ => TaskStatus.blocked,
        },
      );
    }

    await _repository.addEvent(
      FlowRunEventEntity(
        id: const IdVO.empty(),
        runId: runId,
        kind: 'state',
        payload: jsonEncode({'action': action, 'status': status.code}),
      ),
    );
    return result;
  }
}
