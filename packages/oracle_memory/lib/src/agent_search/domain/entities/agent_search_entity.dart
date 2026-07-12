import 'package:oracle_core/oracle_core.dart';

/// One recall an agent made — the tool used, the query, the scope it ran under,
/// the filters, and what came back (ids + scores). Logged automatically so we
/// can audit whether retrieval is delivering what the agent asked for.
class AgentSearchEntity {
  final IdVO id;
  final IdVO? sessionId;
  final IdVO? requestId;

  /// memory | rule | skill | architecture (| rules_for_task).
  final String tool;
  final String query;

  /// {organizationId, projectId, moduleId} — the scope the search ran under.
  final Map<String, dynamic> scope;

  /// Extra filters passed (tiers, kinds, severities, area, mode…).
  final Map<String, dynamic> filters;

  /// [{id, score}, ...] — what was returned, in rank order.
  final List<Map<String, dynamic>> results;
  final int hits;
  final int? latencyMs;
  final DateTime? createdAt;

  const AgentSearchEntity({
    required this.id,
    this.sessionId,
    this.requestId,
    required this.tool,
    required this.query,
    this.scope = const {},
    this.filters = const {},
    this.results = const [],
    this.hits = 0,
    this.latencyMs,
    this.createdAt,
  });
}
