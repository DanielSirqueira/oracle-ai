import 'package:oracle_core/oracle_core.dart';

import '../enums/message_role.dart';

/// A single turn of the agent's work carrying out a request. Belongs to a
/// [requestId] (not directly to a session) — the request is the user's prompt,
/// these messages are the assistant/tool turns answering it.
class MessageEntity {
  final IdVO id;
  final IdVO requestId;
  final MessageRole role;
  final TextVO content;
  final int? tokenCount;
  final List<double>? embedding;
  final String? embeddingModel;
  final DateTime? createdAt;

  const MessageEntity({
    required this.id,
    required this.requestId,
    required this.role,
    required this.content,
    this.tokenCount,
    this.embedding,
    this.embeddingModel,
    this.createdAt,
  });

  MessageEntity copyWith({
    IdVO? id,
    List<double>? embedding,
    String? embeddingModel,
    DateTime? createdAt,
  }) {
    return MessageEntity(
      id: id ?? this.id,
      requestId: requestId,
      role: role,
      content: content,
      tokenCount: tokenCount,
      embedding: embedding ?? this.embedding,
      embeddingModel: embeddingModel ?? this.embeddingModel,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MessageEntity &&
          other.id == id &&
          other.requestId == requestId &&
          other.role == role &&
          other.content == content);

  @override
  int get hashCode => Object.hash(id, requestId, role, content);
}
