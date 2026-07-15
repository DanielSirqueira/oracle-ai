import 'package:collection/collection.dart';
import 'package:oracle_core/oracle_core.dart';

const _listEquality = ListEquality<Object?>();

/// An important decision reached on an RFC — including product decisions, which
/// require [humanApproved] as the human gate. [commentIds] give traceability to
/// the findings that motivated it; [memoryId] is the write-back link to the
/// memory (kind=decision) once the decision is learned, closing the loop.
class RfcDecisionEntity {
  final IdVO id;
  final IdVO rfcId;
  final TextVO question;
  final TextVO chosenOption;
  final TextVO rationale;
  final List<String> commentIds;
  final bool humanApproved;
  final IdVO? memoryId;
  final DateTime? createdAt;

  const RfcDecisionEntity({
    required this.id,
    required this.rfcId,
    required this.question,
    required this.chosenOption,
    required this.rationale,
    this.commentIds = const [],
    this.humanApproved = false,
    this.memoryId,
    this.createdAt,
  });

  RfcDecisionEntity copyWith({
    IdVO? id,
    IdVO? rfcId,
    TextVO? question,
    TextVO? chosenOption,
    TextVO? rationale,
    List<String>? commentIds,
    bool? humanApproved,
    IdVO? memoryId,
    DateTime? createdAt,
  }) {
    return RfcDecisionEntity(
      id: id ?? this.id,
      rfcId: rfcId ?? this.rfcId,
      question: question ?? this.question,
      chosenOption: chosenOption ?? this.chosenOption,
      rationale: rationale ?? this.rationale,
      commentIds: commentIds ?? this.commentIds,
      humanApproved: humanApproved ?? this.humanApproved,
      memoryId: memoryId ?? this.memoryId,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RfcDecisionEntity &&
        other.id == id &&
        other.rfcId == rfcId &&
        other.question == question &&
        other.chosenOption == chosenOption &&
        other.rationale == rationale &&
        _listEquality.equals(other.commentIds, commentIds) &&
        other.humanApproved == humanApproved &&
        other.memoryId == memoryId;
  }

  @override
  int get hashCode => Object.hash(
        id,
        rfcId,
        question,
        chosenOption,
        rationale,
        humanApproved,
        memoryId,
      );
}
