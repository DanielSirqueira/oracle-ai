import 'package:oracle_core/oracle_core.dart';

import '../enums/agent_event_kind.dart';

/// A step the agent took while processing a request (step / reasoning / query /
/// decision / action).
class AgentEventEntity {
  final IdVO id;
  final IdVO requestId;
  final AgentEventKind kind;
  final TextVO content;
  final int? position;
  final DateTime? createdAt;

  const AgentEventEntity({
    required this.id,
    required this.requestId,
    required this.kind,
    required this.content,
    this.position,
    this.createdAt,
  });

  AgentEventEntity copyWith({IdVO? id, DateTime? createdAt}) {
    return AgentEventEntity(
      id: id ?? this.id,
      requestId: requestId,
      kind: kind,
      content: content,
      position: position,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AgentEventEntity &&
          other.id == id &&
          other.requestId == requestId &&
          other.kind == kind &&
          other.content == content);

  @override
  int get hashCode => Object.hash(id, requestId, kind, content);
}
