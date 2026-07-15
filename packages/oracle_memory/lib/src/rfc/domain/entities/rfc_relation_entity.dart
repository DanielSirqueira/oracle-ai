import 'package:collection/collection.dart';
import 'package:oracle_core/oracle_core.dart';

const _listEquality = ListEquality<Object?>();

/// A typed edge in the argumentation graph between two findings — refuting is as
/// demanding as asserting, so a refutation carries its own [evidence]. [relation]
/// is one of supports|refutes|duplicates|supersedes|refines|depends_on; [ground]
/// names WHY (architectural_conflict|business_rule|missing_evidence|out_of_scope|
/// factual_error|redundant).
class RfcRelationEntity {
  final IdVO id;
  final IdVO fromComment;
  final IdVO toComment;
  final String relation;
  final String? ground;
  final TextVO reason;

  /// Evidence backing the edge (a refutation must be grounded too).
  final List<Map<String, dynamic>> evidence;
  final DateTime? createdAt;

  const RfcRelationEntity({
    required this.id,
    required this.fromComment,
    required this.toComment,
    required this.relation,
    this.ground,
    required this.reason,
    this.evidence = const [],
    this.createdAt,
  });

  RfcRelationEntity copyWith({
    IdVO? id,
    IdVO? fromComment,
    IdVO? toComment,
    String? relation,
    String? ground,
    TextVO? reason,
    List<Map<String, dynamic>>? evidence,
    DateTime? createdAt,
  }) {
    return RfcRelationEntity(
      id: id ?? this.id,
      fromComment: fromComment ?? this.fromComment,
      toComment: toComment ?? this.toComment,
      relation: relation ?? this.relation,
      ground: ground ?? this.ground,
      reason: reason ?? this.reason,
      evidence: evidence ?? this.evidence,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RfcRelationEntity &&
        other.id == id &&
        other.fromComment == fromComment &&
        other.toComment == toComment &&
        other.relation == relation &&
        other.ground == ground &&
        other.reason == reason &&
        _listEquality.equals(other.evidence, evidence);
  }

  @override
  int get hashCode => Object.hash(
        id,
        fromComment,
        toComment,
        relation,
        ground,
        reason,
      );
}
