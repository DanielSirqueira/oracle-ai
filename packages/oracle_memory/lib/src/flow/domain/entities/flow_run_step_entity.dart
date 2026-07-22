import 'package:oracle_core/oracle_core.dart';

import '../enums/flow_run_step_status.dart';

/// One interaction of one step (the inner loop). [sessionId] links Oracle's
/// audit transcript; [agentSessionId] is the external CLI conversation reused
/// by later interactions of the same node. [claimToken] is the step's identity
/// in MCP tools. [report]/[verifier] hold the structured outcome and checks.
class FlowRunStepEntity {
  final IdVO id;
  final IdVO runId;
  final IdVO stepId;
  final int iteration;
  final FlowRunStepStatus status;
  final String? agent;
  final IdVO? sessionId;

  /// Conversation id owned by the external agent CLI. Unlike [sessionId],
  /// which points to Oracle's audit transcript, this is passed back through
  /// `--resume` so retries of the same node retain the model's context.
  final String? agentSessionId;
  final String? claimToken;
  final String? renderedPrompt;
  final String? report;
  final String? verifier;
  final int tokensUsed;
  final DateTime? startedAt;
  final DateTime? endedAt;

  const FlowRunStepEntity({
    required this.id,
    required this.runId,
    required this.stepId,
    this.iteration = 1,
    this.status = FlowRunStepStatus.running,
    this.agent,
    this.sessionId,
    this.agentSessionId,
    this.claimToken,
    this.renderedPrompt,
    this.report,
    this.verifier,
    this.tokensUsed = 0,
    this.startedAt,
    this.endedAt,
  });

  FlowRunStepEntity copyWith({
    IdVO? id,
    IdVO? runId,
    IdVO? stepId,
    int? iteration,
    FlowRunStepStatus? status,
    String? agent,
    IdVO? sessionId,
    String? agentSessionId,
    String? claimToken,
    String? renderedPrompt,
    String? report,
    String? verifier,
    int? tokensUsed,
    DateTime? startedAt,
    DateTime? endedAt,
  }) {
    return FlowRunStepEntity(
      id: id ?? this.id,
      runId: runId ?? this.runId,
      stepId: stepId ?? this.stepId,
      iteration: iteration ?? this.iteration,
      status: status ?? this.status,
      agent: agent ?? this.agent,
      sessionId: sessionId ?? this.sessionId,
      agentSessionId: agentSessionId ?? this.agentSessionId,
      claimToken: claimToken ?? this.claimToken,
      renderedPrompt: renderedPrompt ?? this.renderedPrompt,
      report: report ?? this.report,
      verifier: verifier ?? this.verifier,
      tokensUsed: tokensUsed ?? this.tokensUsed,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FlowRunStepEntity &&
        other.id == id &&
        other.runId == runId &&
        other.stepId == stepId &&
        other.iteration == iteration &&
        other.status == status &&
        other.agent == agent &&
        other.sessionId == sessionId &&
        other.agentSessionId == agentSessionId &&
        other.claimToken == claimToken &&
        other.renderedPrompt == renderedPrompt &&
        other.report == report &&
        other.verifier == verifier &&
        other.tokensUsed == tokensUsed;
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    runId,
    stepId,
    iteration,
    status,
    agent,
    sessionId,
    agentSessionId,
    claimToken,
    renderedPrompt,
    report,
    verifier,
    tokensUsed,
  ]);
}
