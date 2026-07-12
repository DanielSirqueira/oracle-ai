import 'package:oracle_core/oracle_core.dart';

import '../entities/agent_event_entity.dart';
import '../entities/message_entity.dart';
import '../entities/request_entity.dart';
import '../entities/session_entity.dart';
import '../errors/capture_failure.dart';

/// Raw capture of agent activity. Mostly fed by lifecycle hooks
/// (fire-and-forget); the reads support recall.
///
/// Shape: a [SessionEntity] IS the agent's own session (no lifecycle). Each user
/// prompt opens a [RequestEntity] (the demand); the agent's work is the
/// [MessageEntity] rows under that request.
abstract interface class CaptureRepository {
  /// Starts (or returns the existing) session — idempotent on (project, agent,
  /// external_id).
  AsyncResultDart<SessionEntity, CaptureFailure> startSession(SessionEntity session);

  /// Opens a new request (one user demand) under a session.
  AsyncResultDart<RequestEntity, CaptureFailure> openRequest(RequestEntity request);

  /// The most recent request of a session (the demand currently in flight).
  /// Fails (CaptureNotFoundFailure) when the session has no request yet — callers
  /// use `.getOrNull()` to treat absence as null.
  AsyncResultDart<RequestEntity, CaptureFailure> latestRequest(IdVO sessionId);

  AsyncResultDart<MessageEntity, CaptureFailure> appendMessage(MessageEntity message);

  /// Adds token usage of a completed turn to the session's rolling aggregate.
  /// Returns the session id on success.
  AsyncResultDart<IdVO, CaptureFailure> addSessionTokens(IdVO sessionId, {int input, int output});

  AsyncResultDart<AgentEventEntity, CaptureFailure> logEvent(AgentEventEntity event);

  /// Messages of a whole session (joined through its requests), oldest first.
  AsyncResultDart<List<MessageEntity>, CaptureFailure> sessionHistory(IdVO sessionId, {int limit});

  /// Requests (user demands) of a session, newest first.
  AsyncResultDart<List<RequestEntity>, CaptureFailure> sessionRequests(IdVO sessionId, {int limit});

  /// Messages of a single request, oldest first.
  AsyncResultDart<List<MessageEntity>, CaptureFailure> requestMessages(IdVO requestId, {int limit});

  /// Semantic search over past user demands of a project.
  AsyncResultDart<List<RequestEntity>, CaptureFailure> searchRequests(
    IdVO projectId,
    List<double> queryEmbedding, {
    int limit,
    String? queryModel,
  });

  AsyncResultDart<List<SessionEntity>, CaptureFailure> recentSessions(IdVO projectId, {int limit});
}
