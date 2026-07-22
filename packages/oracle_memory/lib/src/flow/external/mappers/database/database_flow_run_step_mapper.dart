import 'package:oracle_core/oracle_core.dart';

import '../../../domain/entities/flow_run_step_entity.dart';
import '../../../domain/enums/flow_run_step_status.dart';

/// Maps [FlowRunStepEntity] to/from the `flow_run_steps` table.
class DatabaseFlowRunStepMapper {
  const DatabaseFlowRunStepMapper._();

  static Map<String, Object?> toInsertParams(FlowRunStepEntity s) => {
    'run_id': s.runId.value,
    'step_id': s.stepId.value,
    'iteration': s.iteration,
    'status': s.status.code,
    'agent': s.agent,
    'session_id': s.sessionId?.value,
    'agent_session_id': s.agentSessionId,
    'claim_token': s.claimToken,
    'rendered_prompt': s.renderedPrompt,
    'report': s.report,
    'verifier': s.verifier,
    'tokens_used': s.tokensUsed,
  };

  static FlowRunStepEntity fromRow(Map<String, DataRowType> row) {
    final sessionId = row['session_id']?.toText();
    return FlowRunStepEntity(
      id: IdVO(row['id']!.toText()!),
      runId: IdVO(row['run_id']!.toText()!),
      stepId: IdVO(row['step_id']!.toText()!),
      iteration: row['iteration']?.toInt() ?? 1,
      status: FlowRunStepStatus.parse(row['status']!.toText() ?? 'running'),
      agent: row['agent']?.toText(),
      sessionId: sessionId == null ? null : IdVO(sessionId),
      agentSessionId: row['agent_session_id']?.toText(),
      claimToken: row['claim_token']?.toText(),
      renderedPrompt: row['rendered_prompt']?.toText(),
      report: row['report']?.toText(),
      verifier: row['verifier']?.toText(),
      tokensUsed: row['tokens_used']?.toInt() ?? 0,
      startedAt: row['started_at']?.toDateTime(),
      endedAt: row['ended_at']?.toDateTime(),
    );
  }
}
