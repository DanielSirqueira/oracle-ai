import 'package:oracle_core/oracle_core.dart';

/// Verifiable grounding for a comment (the antidote to hallucination): a
/// reference the Oracle can RESOLVE (a rule/memory/decision/architecture/rfc by
/// id, or a file whose excerpt matches). [resolved] is filled by the tool's
/// validation, not by the agent. [refId] is polymorphic (no rigid FK) when
/// [refKind] is `oracle_entity`.
class RfcEvidenceEntity {
  final IdVO id;
  final IdVO commentId;

  /// rule|memory|decision|architecture|code|api_contract|test|log|data_model|
  /// diagram|business_req|prior_rfc.
  final String kind;

  /// oracle_entity|file|external.
  final String refKind;
  final IdVO? refId;
  final String? locator;
  final String? excerpt;
  final bool resolved;
  final DateTime? resolvedAt;
  final DateTime? createdAt;

  const RfcEvidenceEntity({
    required this.id,
    required this.commentId,
    required this.kind,
    this.refKind = 'oracle_entity',
    this.refId,
    this.locator,
    this.excerpt,
    this.resolved = false,
    this.resolvedAt,
    this.createdAt,
  });

  RfcEvidenceEntity copyWith({
    IdVO? id,
    IdVO? commentId,
    String? kind,
    String? refKind,
    IdVO? refId,
    String? locator,
    String? excerpt,
    bool? resolved,
    DateTime? resolvedAt,
    DateTime? createdAt,
  }) {
    return RfcEvidenceEntity(
      id: id ?? this.id,
      commentId: commentId ?? this.commentId,
      kind: kind ?? this.kind,
      refKind: refKind ?? this.refKind,
      refId: refId ?? this.refId,
      locator: locator ?? this.locator,
      excerpt: excerpt ?? this.excerpt,
      resolved: resolved ?? this.resolved,
      resolvedAt: resolvedAt ?? this.resolvedAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RfcEvidenceEntity &&
        other.id == id &&
        other.commentId == commentId &&
        other.kind == kind &&
        other.refKind == refKind &&
        other.refId == refId &&
        other.locator == locator &&
        other.excerpt == excerpt &&
        other.resolved == resolved;
  }

  @override
  int get hashCode => Object.hash(
        id,
        commentId,
        kind,
        refKind,
        refId,
        locator,
        excerpt,
        resolved,
      );
}
