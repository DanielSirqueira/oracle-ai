import 'package:oracle_core/oracle_core.dart';

import '../enums/flow_step_kind.dart';

/// A node in a flow — and each node is a LOOP. [kind] selects the executor; for
/// `agent` steps [agent]/[model]/[role] pick the harness and persona.
/// [exitCriteria] (raw JSON) are the verifiers the RUNNER runs outside the agent;
/// [outputSchema] is the step's structured-output contract (D7); [permissions] is
/// the least-privilege profile (D8); [maxIterations] bounds the inner loop.
class FlowStepEntity {
  final IdVO id;
  final IdVO flowId;
  final String stepKey;
  final String name;
  final FlowStepKind kind;
  final String? agent;
  final String? model;
  final String? role;
  final String promptTemplate;
  final String? command;
  final String? outputSchema;
  final String permissions;
  final String exitCriteria;
  final int maxIterations;
  final int? tokenBudget;
  final int timeoutMinutes;
  final String onFail;
  final String config;
  final int position;
  final DateTime? createdAt;

  const FlowStepEntity({
    required this.id,
    required this.flowId,
    required this.stepKey,
    this.name = '',
    this.kind = FlowStepKind.agent,
    this.agent,
    this.model,
    this.role,
    this.promptTemplate = '',
    this.command,
    this.outputSchema,
    this.permissions = '{}',
    this.exitCriteria = '{}',
    this.maxIterations = 3,
    this.tokenBudget,
    this.timeoutMinutes = 30,
    this.onFail = 'park',
    this.config = '{}',
    this.position = 0,
    this.createdAt,
  });

  FlowStepEntity copyWith({
    IdVO? id,
    IdVO? flowId,
    String? stepKey,
    String? name,
    FlowStepKind? kind,
    String? agent,
    String? model,
    String? role,
    String? promptTemplate,
    String? command,
    String? outputSchema,
    String? permissions,
    String? exitCriteria,
    int? maxIterations,
    int? tokenBudget,
    int? timeoutMinutes,
    String? onFail,
    String? config,
    int? position,
    DateTime? createdAt,
  }) {
    return FlowStepEntity(
      id: id ?? this.id,
      flowId: flowId ?? this.flowId,
      stepKey: stepKey ?? this.stepKey,
      name: name ?? this.name,
      kind: kind ?? this.kind,
      agent: agent ?? this.agent,
      model: model ?? this.model,
      role: role ?? this.role,
      promptTemplate: promptTemplate ?? this.promptTemplate,
      command: command ?? this.command,
      outputSchema: outputSchema ?? this.outputSchema,
      permissions: permissions ?? this.permissions,
      exitCriteria: exitCriteria ?? this.exitCriteria,
      maxIterations: maxIterations ?? this.maxIterations,
      tokenBudget: tokenBudget ?? this.tokenBudget,
      timeoutMinutes: timeoutMinutes ?? this.timeoutMinutes,
      onFail: onFail ?? this.onFail,
      config: config ?? this.config,
      position: position ?? this.position,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FlowStepEntity &&
        other.id == id &&
        other.flowId == flowId &&
        other.stepKey == stepKey &&
        other.name == name &&
        other.kind == kind &&
        other.agent == agent &&
        other.model == model &&
        other.role == role &&
        other.promptTemplate == promptTemplate &&
        other.command == command &&
        other.outputSchema == outputSchema &&
        other.permissions == permissions &&
        other.exitCriteria == exitCriteria &&
        other.maxIterations == maxIterations &&
        other.tokenBudget == tokenBudget &&
        other.timeoutMinutes == timeoutMinutes &&
        other.onFail == onFail &&
        other.config == config &&
        other.position == position;
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    flowId,
    stepKey,
    name,
    kind,
    agent,
    model,
    role,
    promptTemplate,
    command,
    outputSchema,
    permissions,
    exitCriteria,
    maxIterations,
    tokenBudget,
    timeoutMinutes,
    onFail,
    config,
    position,
  ]);
}
