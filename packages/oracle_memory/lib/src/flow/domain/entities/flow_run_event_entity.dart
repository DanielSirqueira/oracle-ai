import 'package:oracle_core/oracle_core.dart';

/// An append-only timeline entry for a run (audit + Studio): every state
/// transition, verifier result, decision, gate and budget event. [payload] is
/// raw JSON.
class FlowRunEventEntity {
  final IdVO id;
  final IdVO runId;
  final IdVO? runStepId;
  final String kind;
  final String payload;
  final DateTime? createdAt;

  const FlowRunEventEntity({
    required this.id,
    required this.runId,
    this.runStepId,
    required this.kind,
    this.payload = '{}',
    this.createdAt,
  });

  FlowRunEventEntity copyWith({
    IdVO? id,
    IdVO? runId,
    IdVO? runStepId,
    String? kind,
    String? payload,
    DateTime? createdAt,
  }) {
    return FlowRunEventEntity(
      id: id ?? this.id,
      runId: runId ?? this.runId,
      runStepId: runStepId ?? this.runStepId,
      kind: kind ?? this.kind,
      payload: payload ?? this.payload,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FlowRunEventEntity &&
        other.id == id &&
        other.runId == runId &&
        other.runStepId == runStepId &&
        other.kind == kind &&
        other.payload == payload;
  }

  @override
  int get hashCode => Object.hash(id, runId, runStepId, kind, payload);
}
