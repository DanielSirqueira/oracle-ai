import 'package:oracle_core/oracle_core.dart';

/// A user request (demand) within a session — one per user prompt. [userText] is
/// the prompt; it is embedded so past demands are semantically searchable. The
/// agent's work carrying it out is the messages under this request.
class RequestEntity {
  final IdVO id;
  final IdVO sessionId;
  final TextVO userText;
  final List<double>? embedding;
  final String? embeddingModel;
  final DateTime? createdAt;

  const RequestEntity({
    required this.id,
    required this.sessionId,
    required this.userText,
    this.embedding,
    this.embeddingModel,
    this.createdAt,
  });

  RequestEntity copyWith({
    IdVO? id,
    List<double>? embedding,
    String? embeddingModel,
    DateTime? createdAt,
  }) {
    return RequestEntity(
      id: id ?? this.id,
      sessionId: sessionId,
      userText: userText,
      embedding: embedding ?? this.embedding,
      embeddingModel: embeddingModel ?? this.embeddingModel,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RequestEntity &&
          other.id == id &&
          other.sessionId == sessionId &&
          other.userText == userText);

  @override
  int get hashCode => Object.hash(id, sessionId, userText);
}
