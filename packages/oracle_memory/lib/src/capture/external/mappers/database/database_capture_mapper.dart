import 'package:oracle_core/oracle_core.dart';

import '../../../domain/entities/message_entity.dart';
import '../../../domain/entities/request_entity.dart';
import '../../../domain/entities/session_entity.dart';
import '../../../domain/enums/message_role.dart';

class DatabaseCaptureMapper {
  const DatabaseCaptureMapper._();

  // ── session ──
  static Map<String, Object?> sessionParams(SessionEntity s) => {
        'project_id': s.projectId.value,
        'agent': s.agent,
        'external_id': s.externalId,
        'cwd': s.cwd,
      };

  static SessionEntity sessionFromRow(Map<String, DataRowType> r) => SessionEntity(
        id: IdVO(r['id']!.toText()!),
        projectId: IdVO(r['project_id']!.toText()!),
        agent: r['agent']!.toText() ?? '',
        externalId: r['external_id']?.toText(),
        cwd: r['cwd']?.toText(),
        createdAt: r['created_at']?.toDateTime(),
      );

  // ── request ──
  static Map<String, Object?> requestParams(RequestEntity req) => {
        'session_id': req.sessionId.value,
        'user_text': req.userText.value,
        'embedding': req.embedding == null ? null : SqlVector(req.embedding!),
      };

  static RequestEntity requestFromRow(Map<String, DataRowType> r) => RequestEntity(
        id: IdVO(r['id']!.toText()!),
        sessionId: IdVO(r['session_id']!.toText()!),
        userText: TextVO(r['user_text']!.toText() ?? ''),
        embedding: r['embedding']?.toVector(),
        createdAt: r['created_at']?.toDateTime(),
      );

  // ── message ──
  static Map<String, Object?> messageParams(MessageEntity m) => {
        'request_id': m.requestId.value,
        'role': m.role.code,
        'content': m.content.value,
        'token_count': m.tokenCount,
      };

  static MessageEntity messageFromRow(Map<String, DataRowType> r) => MessageEntity(
        id: IdVO(r['id']!.toText()!),
        requestId: IdVO(r['request_id']!.toText()!),
        role: MessageRole.parse(r['role']!.toText() ?? 'assistant'),
        content: TextVO(r['content']!.toText() ?? ''),
        tokenCount: r['token_count']?.toInt(),
        createdAt: r['created_at']?.toDateTime(),
      );

  // ── agent event ──
  static Map<String, Object?> eventParams(IdVO requestId, String kind, String content, int? position) => {
        'request_id': requestId.value,
        'kind': kind,
        'content': content,
        'position': position,
      };
}
