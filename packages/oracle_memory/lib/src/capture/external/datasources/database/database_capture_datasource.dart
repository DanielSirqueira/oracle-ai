import 'package:oracle_core/oracle_core.dart';

import '../../../domain/entities/agent_event_entity.dart';
import '../../../domain/entities/message_entity.dart';
import '../../../domain/entities/request_entity.dart';
import '../../../domain/entities/session_entity.dart';
import '../../../domain/errors/capture_failure.dart';
import '../../../infra/datasources/capture_datasource.dart';
import '../../mappers/database/database_capture_mapper.dart';

class DatabaseCaptureDatasource implements CaptureDatasource {
  final Database _database;
  const DatabaseCaptureDatasource({required Database database}) : _database = database;

  static const _sessionColumns = 'id, project_id, agent, external_id, cwd, created_at';
  static const _messageColumns = 'id, request_id, role, content, token_count, created_at';
  // embedding cast to text so DataRowType.toVector() can parse it on read.
  static const _requestColumns =
      'id, session_id, user_text, embedding::text AS embedding, created_at';

  @override
  Future<SessionEntity> startSession(SessionEntity session) async {
    try {
      // Idempotent on (project, agent, external_id): the agent's session id is
      // the identity, so re-seeing it returns the existing row.
      final result = await _database.executeUpdate(SqlStatement(
        'INSERT INTO sessions (project_id, agent, external_id, cwd) '
        'VALUES (:project_id::uuid, :agent, :external_id, :cwd) '
        'ON CONFLICT (project_id, agent, external_id) DO UPDATE SET cwd = EXCLUDED.cwd '
        'RETURNING $_sessionColumns',
        DatabaseCaptureMapper.sessionParams(session),
      ));
      return DatabaseCaptureMapper.sessionFromRow(result.rows.first);
    } on DatabaseFailure catch (e) {
      throw DatasourceCaptureFailure(errorMessage: e.errorMessage, stackTrace: StackTrace.current);
    }
  }

  @override
  Future<RequestEntity> openRequest(RequestEntity request) async {
    try {
      final result = await _database.executeUpdate(SqlStatement(
        'INSERT INTO requests (session_id, user_text, embedding, embedding_model) '
        'VALUES (:session_id::uuid, :user_text, :embedding::vector(1024), :embedding_model) '
        'RETURNING id, created_at',
        DatabaseCaptureMapper.requestParams(request),
      ));
      final row = result.rows.first;
      return request.copyWith(
        id: IdVO(row['id']!.toText()!),
        createdAt: row['created_at']?.toDateTime(),
      );
    } on DatabaseFailure catch (e) {
      throw DatasourceCaptureFailure(errorMessage: e.errorMessage, stackTrace: StackTrace.current);
    }
  }

  @override
  Future<RequestEntity> latestRequest(IdVO sessionId) async {
    try {
      final result = await _database.select(SqlStatement(
        'SELECT $_requestColumns FROM requests WHERE session_id = :sid::uuid '
        'ORDER BY created_at DESC LIMIT 1',
        {'sid': sessionId.value},
      ));
      if (result.rows.isEmpty) {
        throw CaptureNotFoundFailure(stackTrace: StackTrace.current);
      }
      return DatabaseCaptureMapper.requestFromRow(result.rows.first);
    } on DatabaseFailure catch (e) {
      throw DatasourceCaptureFailure(errorMessage: e.errorMessage, stackTrace: StackTrace.current);
    }
  }

  @override
  Future<MessageEntity> appendMessage(MessageEntity message) async {
    try {
      final result = await _database.executeUpdate(SqlStatement(
        'INSERT INTO messages (request_id, role, content, token_count) '
        'VALUES (:request_id::uuid, :role, :content, :token_count) '
        'RETURNING id, created_at',
        DatabaseCaptureMapper.messageParams(message),
      ));
      final row = result.rows.first;
      return message.copyWith(id: IdVO(row['id']!.toText()!), createdAt: row['created_at']?.toDateTime());
    } on DatabaseFailure catch (e) {
      throw DatasourceCaptureFailure(errorMessage: e.errorMessage, stackTrace: StackTrace.current);
    }
  }

  @override
  Future<AgentEventEntity> logEvent(AgentEventEntity event) async {
    try {
      final result = await _database.executeUpdate(SqlStatement(
        'INSERT INTO agent_events (request_id, kind, content, position) '
        'VALUES (:request_id::uuid, :kind, :content, :position) '
        'RETURNING id, created_at',
        DatabaseCaptureMapper.eventParams(event.requestId, event.kind.code, event.content.value, event.position),
      ));
      final row = result.rows.first;
      return event.copyWith(id: IdVO(row['id']!.toText()!), createdAt: row['created_at']?.toDateTime());
    } on DatabaseFailure catch (e) {
      throw DatasourceCaptureFailure(errorMessage: e.errorMessage, stackTrace: StackTrace.current);
    }
  }

  @override
  Future<List<MessageEntity>> sessionHistory(IdVO sessionId, {int limit = 40}) async {
    try {
      // Messages hang off requests now; join through to scope by session.
      // MOST RECENT FIRST + LIMIT, so a long session surfaces the latest work
      // (not the oldest) and the payload stays bounded.
      final result = await _database.select(SqlStatement(
        'SELECT ${_prefixed(_messageColumns, 'm')} FROM messages m '
        'JOIN requests r ON r.id = m.request_id '
        'WHERE r.session_id = :sid::uuid '
        'ORDER BY m.created_at DESC LIMIT :limit',
        {'sid': sessionId.value, 'limit': limit},
      ));
      return result.rows.map(DatabaseCaptureMapper.messageFromRow).toList();
    } on DatabaseFailure catch (e) {
      throw DatasourceCaptureFailure(errorMessage: e.errorMessage, stackTrace: StackTrace.current);
    }
  }

  @override
  Future<List<RequestEntity>> sessionRequests(IdVO sessionId, {int limit = 50}) async {
    try {
      final result = await _database.select(SqlStatement(
        'SELECT $_requestColumns FROM requests WHERE session_id = :sid::uuid '
        'ORDER BY created_at DESC LIMIT :limit',
        {'sid': sessionId.value, 'limit': limit},
      ));
      return result.rows.map(DatabaseCaptureMapper.requestFromRow).toList();
    } on DatabaseFailure catch (e) {
      throw DatasourceCaptureFailure(errorMessage: e.errorMessage, stackTrace: StackTrace.current);
    }
  }

  @override
  Future<List<MessageEntity>> requestMessages(IdVO requestId, {int limit = 100}) async {
    try {
      final result = await _database.select(SqlStatement(
        'SELECT $_messageColumns FROM messages WHERE request_id = :rid::uuid '
        'ORDER BY created_at LIMIT :limit',
        {'rid': requestId.value, 'limit': limit},
      ));
      return result.rows.map(DatabaseCaptureMapper.messageFromRow).toList();
    } on DatabaseFailure catch (e) {
      throw DatasourceCaptureFailure(errorMessage: e.errorMessage, stackTrace: StackTrace.current);
    }
  }

  @override
  Future<List<RequestEntity>> searchRequests(
    IdVO projectId,
    List<double> queryEmbedding, {
    int limit = 10,
    String? queryModel,
  }) async {
    try {
      final params = <String, Object?>{
        'pid': projectId.value,
        'qvec': SqlVector(queryEmbedding),
        'limit': limit,
      };
      // Compare only same-model vectors when the caller declares the query model —
      // cross-model cosine distances are meaningless (mirrors memory/rule/arch).
      var modelFilter = '';
      if (queryModel != null && queryModel.isNotEmpty) {
        modelFilter = 'AND r.embedding_model = :qmodel ';
        params['qmodel'] = queryModel;
      }
      // Semantic search over the project's past demands, joined through sessions.
      final result = await _database.select(SqlStatement(
        'SELECT ${_prefixed(_requestColumns, 'r')} FROM requests r '
        'JOIN sessions s ON s.id = r.session_id '
        'WHERE s.project_id = :pid::uuid AND r.embedding IS NOT NULL $modelFilter'
        'ORDER BY r.embedding <=> :qvec::vector(1024) LIMIT :limit',
        params,
      ));
      return result.rows.map(DatabaseCaptureMapper.requestFromRow).toList();
    } on DatabaseFailure catch (e) {
      throw DatasourceCaptureFailure(errorMessage: e.errorMessage, stackTrace: StackTrace.current);
    }
  }

  @override
  Future<List<SessionEntity>> recentSessions(IdVO projectId, {int limit = 20}) async {
    try {
      final result = await _database.select(SqlStatement(
        'SELECT $_sessionColumns FROM sessions WHERE project_id = :pid::uuid '
        'ORDER BY created_at DESC LIMIT :limit',
        {'pid': projectId.value, 'limit': limit},
      ));
      return result.rows.map(DatabaseCaptureMapper.sessionFromRow).toList();
    } on DatabaseFailure catch (e) {
      throw DatasourceCaptureFailure(errorMessage: e.errorMessage, stackTrace: StackTrace.current);
    }
  }

  /// Prefix a bare column list with a table alias (`id, x` → `m.id, m.x`),
  /// leaving `expr::text AS alias` projections untouched on their leading column.
  static String _prefixed(String columns, String alias) =>
      columns.split(', ').map((c) => '$alias.$c').join(', ');
}
