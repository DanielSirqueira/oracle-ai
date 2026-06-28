import 'package:oracle_core/oracle_core.dart';

import '../enums/handoff_status.dart';

/// A handoff baton — the state passed between sessions/agents so work continues
/// without re-explaining context.
class HandoffEntity {
  final IdVO id;
  final IdVO projectId;
  final IdVO? sourceSessionId;
  final String? fromAgent;
  final String? toAgent;
  final TextVO summary;
  final List<String> openQuestions;
  final List<String> nextSteps;
  final List<String> filesTouched;
  final HandoffStatus status;
  final String? cwd;
  final DateTime? createdAt;
  final DateTime? acceptedAt;

  const HandoffEntity({
    required this.id,
    required this.projectId,
    this.sourceSessionId,
    this.fromAgent,
    this.toAgent,
    required this.summary,
    this.openQuestions = const [],
    this.nextSteps = const [],
    this.filesTouched = const [],
    this.status = HandoffStatus.open,
    this.cwd,
    this.createdAt,
    this.acceptedAt,
  });

  factory HandoffEntity.empty() =>
      const HandoffEntity(id: IdVO.empty(), projectId: IdVO.empty(), summary: TextVO.empty());

  HandoffEntity copyWith({
    IdVO? id,
    HandoffStatus? status,
    DateTime? createdAt,
    DateTime? acceptedAt,
  }) {
    return HandoffEntity(
      id: id ?? this.id,
      projectId: projectId,
      sourceSessionId: sourceSessionId,
      fromAgent: fromAgent,
      toAgent: toAgent,
      summary: summary,
      openQuestions: openQuestions,
      nextSteps: nextSteps,
      filesTouched: filesTouched,
      status: status ?? this.status,
      cwd: cwd,
      createdAt: createdAt ?? this.createdAt,
      acceptedAt: acceptedAt ?? this.acceptedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is HandoffEntity &&
        other.id == id &&
        other.projectId == projectId &&
        other.summary == summary &&
        other.status == status;
  }

  @override
  int get hashCode => Object.hash(id, projectId, summary, status);
}
