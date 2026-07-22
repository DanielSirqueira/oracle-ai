import 'package:oracle_core/oracle_core.dart';

/// A directed edge in a flow graph (the "wiring" between loops). [condition]
/// routes on the verifier outcome (`success`/`failure`), the step agent's
/// choice (`verdict`, matched against [verdictValue]), or `always`.
/// [instruction] (verdict edges) tells the agent WHEN to take this route —
/// it is rendered into the prompt next to the verdict value, which makes ANY
/// agent node a decision point, not just a dedicated decision step.
class FlowEdgeEntity {
  final IdVO id;
  final IdVO flowId;
  final IdVO fromStep;
  final IdVO toStep;
  final String condition;
  final String? verdictValue;
  final String? instruction;
  final DateTime? createdAt;

  const FlowEdgeEntity({
    required this.id,
    required this.flowId,
    required this.fromStep,
    required this.toStep,
    this.condition = 'success',
    this.verdictValue,
    this.instruction,
    this.createdAt,
  });

  FlowEdgeEntity copyWith({
    IdVO? id,
    IdVO? flowId,
    IdVO? fromStep,
    IdVO? toStep,
    String? condition,
    String? verdictValue,
    String? instruction,
    DateTime? createdAt,
  }) {
    return FlowEdgeEntity(
      id: id ?? this.id,
      flowId: flowId ?? this.flowId,
      fromStep: fromStep ?? this.fromStep,
      toStep: toStep ?? this.toStep,
      condition: condition ?? this.condition,
      verdictValue: verdictValue ?? this.verdictValue,
      instruction: instruction ?? this.instruction,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FlowEdgeEntity &&
        other.id == id &&
        other.flowId == flowId &&
        other.fromStep == fromStep &&
        other.toStep == toStep &&
        other.condition == condition &&
        other.verdictValue == verdictValue &&
        other.instruction == instruction;
  }

  @override
  int get hashCode => Object.hash(
    id,
    flowId,
    fromStep,
    toStep,
    condition,
    verdictValue,
    instruction,
  );
}
