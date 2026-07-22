import 'package:oracle_core/oracle_core.dart';

/// One key→value entry of a run's blackboard. The steps read and write it
/// (plan, rfc_id, findings_summary…); the next agent depends on what was
/// STRUCTURALLY written here, never on the previous agent's transcript
/// (anti context-rot). [value] is raw JSON.
class FlowRunContextEntity {
  final IdVO runId;
  final String key;
  final String value;
  final IdVO? updatedBy;
  final DateTime? updatedAt;

  const FlowRunContextEntity({
    required this.runId,
    required this.key,
    this.value = '{}',
    this.updatedBy,
    this.updatedAt,
  });

  FlowRunContextEntity copyWith({
    IdVO? runId,
    String? key,
    String? value,
    IdVO? updatedBy,
    DateTime? updatedAt,
  }) {
    return FlowRunContextEntity(
      runId: runId ?? this.runId,
      key: key ?? this.key,
      value: value ?? this.value,
      updatedBy: updatedBy ?? this.updatedBy,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FlowRunContextEntity &&
        other.runId == runId &&
        other.key == key &&
        other.value == value &&
        other.updatedBy == updatedBy;
  }

  @override
  int get hashCode => Object.hash(runId, key, value, updatedBy);
}
