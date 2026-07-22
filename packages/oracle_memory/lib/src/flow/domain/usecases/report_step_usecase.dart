import 'dart:convert';

import 'package:oracle_core/oracle_core.dart';

import '../entities/flow_run_event_entity.dart';
import '../entities/flow_run_step_entity.dart';
import '../enums/flow_run_step_status.dart';
import '../errors/flow_failure.dart';
import '../repositories/flow_repository.dart';

/// Closes a step from the agent's side (`oracle_flow_step_report`) — the
/// structured handoff. Stores the report and moves the run-step to `verifying`
/// (the runner verifies outside the agent) or `parked` when the agent is blocked.
/// This is the trigger for the runner to run the verifiers and advance.
abstract interface class ReportStepUsecase {
  AsyncResultDart<FlowRunStepEntity, FlowFailure> call(
    IdVO runStepId, {
    required String reportJson,
    bool blocked = false,
    String? claimToken,
  });
}

class ReportStepUsecaseImpl implements ReportStepUsecase {
  final FlowRepository _repository;
  const ReportStepUsecaseImpl(this._repository);

  @override
  AsyncResultDart<FlowRunStepEntity, FlowFailure> call(
    IdVO runStepId, {
    required String reportJson,
    bool blocked = false,
    String? claimToken,
  }) async {
    final currentResult = await _repository.getRunStep(runStepId);
    if (currentResult.isError()) return currentResult;
    final current = currentResult.getOrThrow();
    if (current.status != FlowRunStepStatus.running &&
        current.status != FlowRunStepStatus.verifying) {
      return Failure(
        ValidatedFieldFlowFailure(
          errorMessage: 'This step attempt is no longer active',
          stackTrace: StackTrace.current,
          fields: const [
            FieldSystemFailure(
              field: 'status',
              message: 'Expected running or verifying',
            ),
          ],
        ),
      );
    }
    if (current.claimToken != null && claimToken != current.claimToken) {
      return Failure(
        ValidatedFieldFlowFailure(
          errorMessage:
              'Invalid or stale step claim token — pass the claimToken exactly as '
              'given in your step prompt, or fetch it via oracle_flow_step_context '
              '(runStep.claimToken)',
          stackTrace: StackTrace.current,
          fields: const [
            FieldSystemFailure(
              field: 'claimToken',
              message: 'Does not own this attempt',
            ),
          ],
        ),
      );
    }

    final updated = current.copyWith(
      report: reportJson,
      status: blocked ? FlowRunStepStatus.parked : FlowRunStepStatus.verifying,
    );
    final result = await _repository.updateRunStep(updated);
    if (result.isError()) return result;

    await _repository.addEvent(
      FlowRunEventEntity(
        id: const IdVO.empty(),
        runId: current.runId,
        runStepId: runStepId,
        kind: 'step_end',
        payload: jsonEncode({'blocked': blocked}),
      ),
    );
    return result;
  }
}
