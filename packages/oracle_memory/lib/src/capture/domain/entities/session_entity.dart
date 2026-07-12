import 'package:oracle_core/oracle_core.dart';

/// An agent session within a project — identified by the agent's OWN session id
/// ([externalId], delivered by the hook). No status/lifecycle: the agent resumes
/// the same session whenever it wants, so Oracle just keeps it as a stable id.
class SessionEntity {
  final IdVO id;
  final IdVO projectId;
  final String agent;
  final String? externalId;
  final String? cwd;
  final DateTime? createdAt;

  /// Rolling token totals for the session (summed from completed turns).
  final int inputTokens;
  final int outputTokens;
  final int totalTokens;

  const SessionEntity({
    required this.id,
    required this.projectId,
    required this.agent,
    this.externalId,
    this.cwd,
    this.createdAt,
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.totalTokens = 0,
  });

  SessionEntity copyWith({IdVO? id, DateTime? createdAt}) {
    return SessionEntity(
      id: id ?? this.id,
      projectId: projectId,
      agent: agent,
      externalId: externalId,
      cwd: cwd,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SessionEntity &&
          other.id == id &&
          other.projectId == projectId &&
          other.agent == agent &&
          other.externalId == externalId);

  @override
  int get hashCode => Object.hash(id, projectId, agent, externalId);
}
