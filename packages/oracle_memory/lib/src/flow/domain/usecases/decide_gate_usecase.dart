import 'dart:convert';

import 'package:oracle_core/oracle_core.dart';

import '../entities/flow_run_entity.dart';
import '../entities/flow_run_event_entity.dart';
import '../enums/flow_run_status.dart';
import '../enums/task_status.dart';
import '../errors/flow_failure.dart';
import '../repositories/flow_repository.dart';

/// Resolves a human gate on a run parked in `awaiting_human`. Approval releases
/// the run back to `running` (the worker picks it up); rejection fails it. The
/// decision is stamped on the timeline (the human-in-the-loop audit).
abstract interface class DecideGateUsecase {
  AsyncResultDart<FlowRunEntity, FlowFailure> call(
    IdVO runId, {
    required bool approved,
    String? reason,
  });
}

class DecideGateUsecaseImpl implements DecideGateUsecase {
  final FlowRepository _repository;
  const DecideGateUsecaseImpl(this._repository);

  @override
  AsyncResultDart<FlowRunEntity, FlowFailure> call(
    IdVO runId, {
    required bool approved,
    String? reason,
  }) async {
    final currentResult = await _repository.getRun(runId);
    if (currentResult.isError()) {
      return Failure(currentResult.exceptionOrNull()!);
    }
    final current = currentResult.getOrThrow().run;
    if (current.status != FlowRunStatus.awaitingHuman) {
      return Failure(
        ValidatedFieldFlowFailure(
          errorMessage: 'Run is not waiting for a human decision',
          stackTrace: StackTrace.current,
          fields: const [
            FieldSystemFailure(
              field: 'status',
              message: 'Expected awaiting_human',
            ),
          ],
        ),
      );
    }

    // Approval re-enqueues (queued) so a worker re-claims and resumes past the
    // gate; rejection fails the run.
    final status = approved ? FlowRunStatus.queued : FlowRunStatus.failed;
    final result = await _repository.updateRunStatus(
      runId,
      status,
      error: approved ? null : (reason ?? 'Rejected at human gate'),
      expectedStatuses: const {FlowRunStatus.awaitingHuman},
    );
    if (result.isError()) return result;

    if (current.taskId != null) {
      await _repository.updateTask(
        current.taskId!,
        status: approved ? TaskStatus.ready : TaskStatus.blocked,
      );
    }

    await _repository.addEvent(
      FlowRunEventEntity(
        id: const IdVO.empty(),
        runId: runId,
        kind: 'gate',
        payload: jsonEncode({'approved': approved, 'reason': reason ?? ''}),
      ),
    );
    return result;
  }
}
