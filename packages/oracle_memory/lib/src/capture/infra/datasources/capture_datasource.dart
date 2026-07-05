import 'package:oracle_core/oracle_core.dart';

import '../../domain/entities/agent_event_entity.dart';
import '../../domain/entities/message_entity.dart';
import '../../domain/entities/request_entity.dart';
import '../../domain/entities/session_entity.dart';

abstract interface class CaptureDatasource {
  Future<SessionEntity> startSession(SessionEntity session);

  Future<RequestEntity> openRequest(RequestEntity request);

  /// The most recent request of a session (the demand currently in flight).
  /// Throws CaptureNotFoundFailure when the session has no request yet.
  Future<RequestEntity> latestRequest(IdVO sessionId);

  Future<MessageEntity> appendMessage(MessageEntity message);

  Future<AgentEventEntity> logEvent(AgentEventEntity event);

  /// Messages of a whole session (joined through its requests), oldest first.
  Future<List<MessageEntity>> sessionHistory(IdVO sessionId, {int limit});

  /// Requests (user demands) of a session, newest first.
  Future<List<RequestEntity>> sessionRequests(IdVO sessionId, {int limit});

  /// Messages of a single request, oldest first.
  Future<List<MessageEntity>> requestMessages(IdVO requestId, {int limit});

  /// Semantic search over past user demands of a project (vector distance).
  Future<List<RequestEntity>> searchRequests(
    IdVO projectId,
    List<double> queryEmbedding, {
    int limit,
    String? queryModel,
  });

  Future<List<SessionEntity>> recentSessions(IdVO projectId, {int limit});
}
