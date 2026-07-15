import 'package:oracle_core/oracle_core.dart';

/// The recorded outcome of a finding — its [decision] (accepted|rejected|
/// deferred|duplicate) plus the [reason] (audit trail). May cite the [ruleId] of
/// the required rule that invalidated the finding. Resolving a comment also
/// stamps the comment's own status with [decision].
class RfcResolutionEntity {
  final IdVO id;
  final IdVO commentId;
  final String resolverAgent;

  /// accepted|rejected|deferred|duplicate — mirrors the comment's target status.
  final String decision;
  final String? ground;
  final TextVO reason;

  /// The `required` rule that invalidated the finding (optional).
  final IdVO? ruleId;
  final DateTime? decidedAt;

  const RfcResolutionEntity({
    required this.id,
    required this.commentId,
    this.resolverAgent = 'claude-code',
    required this.decision,
    this.ground,
    required this.reason,
    this.ruleId,
    this.decidedAt,
  });

  RfcResolutionEntity copyWith({
    IdVO? id,
    IdVO? commentId,
    String? resolverAgent,
    String? decision,
    String? ground,
    TextVO? reason,
    IdVO? ruleId,
    DateTime? decidedAt,
  }) {
    return RfcResolutionEntity(
      id: id ?? this.id,
      commentId: commentId ?? this.commentId,
      resolverAgent: resolverAgent ?? this.resolverAgent,
      decision: decision ?? this.decision,
      ground: ground ?? this.ground,
      reason: reason ?? this.reason,
      ruleId: ruleId ?? this.ruleId,
      decidedAt: decidedAt ?? this.decidedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RfcResolutionEntity &&
        other.id == id &&
        other.commentId == commentId &&
        other.resolverAgent == resolverAgent &&
        other.decision == decision &&
        other.ground == ground &&
        other.reason == reason &&
        other.ruleId == ruleId;
  }

  @override
  int get hashCode => Object.hash(
        id,
        commentId,
        resolverAgent,
        decision,
        ground,
        reason,
        ruleId,
      );
}
