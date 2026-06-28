import 'dart:convert';

import 'package:oracle_core/oracle_core.dart';

import '../../../domain/entities/handoff_entity.dart';
import '../../../domain/enums/handoff_status.dart';

class DatabaseHandoffMapper {
  const DatabaseHandoffMapper._();

  /// jsonb columns are sent as JSON text and cast in SQL (`:x::jsonb`).
  static Map<String, Object?> toInsertParams(HandoffEntity h) => {
        'project_id': h.projectId.value,
        'source_session_id': h.sourceSessionId?.value,
        'from_agent': h.fromAgent,
        'to_agent': h.toAgent,
        'summary': h.summary.value,
        'open_questions': jsonEncode(h.openQuestions),
        'next_steps': jsonEncode(h.nextSteps),
        'files_touched': jsonEncode(h.filesTouched),
        'cwd': h.cwd,
      };

  static HandoffEntity fromRow(Map<String, DataRowType> row) {
    final sourceSession = row['source_session_id']?.toText();
    return HandoffEntity(
      id: IdVO(row['id']!.toText()!),
      projectId: IdVO(row['project_id']!.toText()!),
      sourceSessionId: sourceSession == null ? null : IdVO(sourceSession),
      fromAgent: row['from_agent']?.toText(),
      toAgent: row['to_agent']?.toText(),
      summary: TextVO(row['summary']!.toText() ?? ''),
      openQuestions: row['open_questions']?.toStringList() ?? const [],
      nextSteps: row['next_steps']?.toStringList() ?? const [],
      filesTouched: row['files_touched']?.toStringList() ?? const [],
      status: HandoffStatus.parse(row['status']!.toText() ?? 'open'),
      cwd: row['cwd']?.toText(),
      createdAt: row['created_at']?.toDateTime(),
      acceptedAt: row['accepted_at']?.toDateTime(),
    );
  }
}
