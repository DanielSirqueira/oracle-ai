import 'package:oracle_core/oracle_core.dart';

import '../../domain/entities/agent_event_entity.dart';
import '../../domain/entities/message_entity.dart';
import '../../domain/entities/request_entity.dart';
import '../../domain/entities/session_entity.dart';
import '../../domain/errors/capture_failure.dart';
import '../../domain/repositories/capture_repository.dart';
import '../datasources/capture_datasource.dart';

class CaptureRepositoryImpl implements CaptureRepository {
  final CaptureDatasource _datasource;
  const CaptureRepositoryImpl({required CaptureDatasource datasource}) : _datasource = datasource;

  @override
  AsyncResultDart<SessionEntity, CaptureFailure> startSession(SessionEntity session) async {
    try {
      return Success(await _datasource.startSession(session));
    } on CaptureFailure catch (f) {
      return Failure(f);
    }
  }

  @override
  AsyncResultDart<RequestEntity, CaptureFailure> openRequest(RequestEntity request) async {
    try {
      return Success(await _datasource.openRequest(request));
    } on CaptureFailure catch (f) {
      return Failure(f);
    }
  }

  @override
  AsyncResultDart<RequestEntity, CaptureFailure> latestRequest(IdVO sessionId) async {
    try {
      return Success(await _datasource.latestRequest(sessionId));
    } on CaptureFailure catch (f) {
      return Failure(f);
    }
  }

  @override
  AsyncResultDart<MessageEntity, CaptureFailure> appendMessage(MessageEntity message) async {
    try {
      return Success(await _datasource.appendMessage(message));
    } on CaptureFailure catch (f) {
      return Failure(f);
    }
  }

  @override
  AsyncResultDart<AgentEventEntity, CaptureFailure> logEvent(AgentEventEntity event) async {
    try {
      return Success(await _datasource.logEvent(event));
    } on CaptureFailure catch (f) {
      return Failure(f);
    }
  }

  @override
  AsyncResultDart<List<MessageEntity>, CaptureFailure> sessionHistory(
    IdVO sessionId, {
    int limit = 40,
  }) async {
    try {
      return Success(await _datasource.sessionHistory(sessionId, limit: limit));
    } on CaptureFailure catch (f) {
      return Failure(f);
    }
  }

  @override
  AsyncResultDart<List<RequestEntity>, CaptureFailure> sessionRequests(
    IdVO sessionId, {
    int limit = 50,
  }) async {
    try {
      return Success(await _datasource.sessionRequests(sessionId, limit: limit));
    } on CaptureFailure catch (f) {
      return Failure(f);
    }
  }

  @override
  AsyncResultDart<List<MessageEntity>, CaptureFailure> requestMessages(
    IdVO requestId, {
    int limit = 100,
  }) async {
    try {
      return Success(await _datasource.requestMessages(requestId, limit: limit));
    } on CaptureFailure catch (f) {
      return Failure(f);
    }
  }

  @override
  AsyncResultDart<List<RequestEntity>, CaptureFailure> searchRequests(
    IdVO projectId,
    List<double> queryEmbedding, {
    int limit = 10,
  }) async {
    try {
      return Success(await _datasource.searchRequests(projectId, queryEmbedding, limit: limit));
    } on CaptureFailure catch (f) {
      return Failure(f);
    }
  }

  @override
  AsyncResultDart<List<SessionEntity>, CaptureFailure> recentSessions(
    IdVO projectId, {
    int limit = 20,
  }) async {
    try {
      return Success(await _datasource.recentSessions(projectId, limit: limit));
    } on CaptureFailure catch (f) {
      return Failure(f);
    }
  }
}
