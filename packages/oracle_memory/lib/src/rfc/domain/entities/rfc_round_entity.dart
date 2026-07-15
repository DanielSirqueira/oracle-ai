import 'package:collection/collection.dart';
import 'package:oracle_core/oracle_core.dart';

const _listEquality = ListEquality<Object?>();

/// One review cycle of an RFC. [noveltyScore] (0..1, the non-duplicated fraction
/// of the round's findings) feeds multi-criteria termination and non-progress
/// detection; [newCriticals]/[newMajors] track the round's yield. [participants]
/// are the agents/roles that reviewed.
class RfcRoundEntity {
  final IdVO id;
  final IdVO rfcId;
  final IdVO? versionId;
  final int roundNo;
  final List<String> participants;
  final int newCriticals;
  final int newMajors;
  final double? noveltyScore;
  final DateTime? startedAt;
  final DateTime? endedAt;

  const RfcRoundEntity({
    required this.id,
    required this.rfcId,
    this.versionId,
    required this.roundNo,
    this.participants = const [],
    this.newCriticals = 0,
    this.newMajors = 0,
    this.noveltyScore,
    this.startedAt,
    this.endedAt,
  });

  RfcRoundEntity copyWith({
    IdVO? id,
    IdVO? rfcId,
    IdVO? versionId,
    int? roundNo,
    List<String>? participants,
    int? newCriticals,
    int? newMajors,
    double? noveltyScore,
    DateTime? startedAt,
    DateTime? endedAt,
  }) {
    return RfcRoundEntity(
      id: id ?? this.id,
      rfcId: rfcId ?? this.rfcId,
      versionId: versionId ?? this.versionId,
      roundNo: roundNo ?? this.roundNo,
      participants: participants ?? this.participants,
      newCriticals: newCriticals ?? this.newCriticals,
      newMajors: newMajors ?? this.newMajors,
      noveltyScore: noveltyScore ?? this.noveltyScore,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RfcRoundEntity &&
        other.id == id &&
        other.rfcId == rfcId &&
        other.versionId == versionId &&
        other.roundNo == roundNo &&
        _listEquality.equals(other.participants, participants) &&
        other.newCriticals == newCriticals &&
        other.newMajors == newMajors &&
        other.noveltyScore == noveltyScore;
  }

  @override
  int get hashCode => Object.hash(
        id,
        rfcId,
        versionId,
        roundNo,
        newCriticals,
        newMajors,
        noveltyScore,
      );
}
