import 'package:oracle_core/oracle_core.dart';
import 'package:oracle_memory/oracle_memory.dart';

/// Assembles the text the memory bank INJECTS into the agent's context via
/// hooks. Two cache-aware shapes:
///
/// - [sessionBrief]: a stable, once-per-session digest (pending handoff +
///   required rules + top memories) for the SessionStart hook. Goes in early,
///   rarely changes — cache-friendly.
/// - [promptRecall]: a small, query-gated slice for the UserPromptSubmit hook.
///   Returns null when nothing is relevant, so we never inject noise (and never
///   churn the cache) on unrelated turns.
class RecallService {
  const RecallService();

  /// Max characters of any single memory/rule body rendered into context.
  static const _snippetChars = 240;

  Future<String?> sessionBrief(IdVO projectId) async {
    final handoff = await _pendingHandoff(projectId);
    final rules = await _requiredRules(projectId);
    final memories = await _topMemories(projectId);
    if (handoff == null && rules.isEmpty && memories.isEmpty) return null;

    final b = StringBuffer('# Oracle AI — session brief\n');
    if (handoff != null) {
      b.writeln('\n## Continue from the previous session');
      b.writeln(_snippet(handoff.summary.value));
      if (handoff.openQuestions.isNotEmpty) {
        b.writeln('Open questions: ${handoff.openQuestions.join('; ')}');
      }
      if (handoff.nextSteps.isNotEmpty) {
        b.writeln('Next steps: ${handoff.nextSteps.join('; ')}');
      }
    }
    if (rules.isNotEmpty) {
      b.writeln('\n## Required project rules (follow these)');
      for (final r in rules) {
        b.writeln('- [${r.scope}] ${r.title.value} — ${_snippet(r.content.value)}');
      }
    }
    if (memories.isNotEmpty) {
      b.writeln('\n## Key project memories');
      for (final m in memories) {
        b.writeln('- (${m.kind.code}) ${m.title.value} — ${_snippet(m.body.value)}');
      }
    }
    b.writeln('\n_Save durable decisions/gotchas with oracle_memory_save; '
        'consult oracle_rules_for_task before coding._');
    return b.toString();
  }

  Future<String?> promptRecall(IdVO projectId, String prompt) async {
    if (prompt.trim().isEmpty) return null;
    // Distance-gated: returns empty when nothing is genuinely close, so an
    // unrelated turn injects nothing (no noise, no cache churn).
    final result = await injector.get<RelevantMemoriesUsecase>()(
      projectId,
      prompt,
      maxDistance: 0.6,
      limit: 3,
    );
    return _renderRecall(result.getOrNull() ?? const []);
  }

  /// Like [promptRecall] but reusing a precomputed prompt embedding (the
  /// UserPromptSubmit hook embeds the prompt once for the request row and shares
  /// it here, avoiding a second embedding call). Null embedding → no recall.
  Future<String?> promptRecallFor(IdVO projectId, List<double>? embedding) async {
    if (embedding == null) return null;
    final result =
        await injector.get<MemoryRepository>().relevantMemories(projectId, embedding, 0.6, 3);
    return _renderRecall(result.getOrNull() ?? const []);
  }

  String? _renderRecall(List<MemoryEntity> hits) {
    if (hits.isEmpty) return null;
    final b = StringBuffer('# Oracle AI — recalled context (relevant to your request)\n');
    for (final m in hits) {
      b.writeln('- (${m.kind.code}) ${m.title.value} — ${_snippet(m.body.value)}');
    }
    return b.toString();
  }

  // ── helpers ──

  Future<HandoffEntity?> _pendingHandoff(IdVO projectId) async {
    final result = await injector.get<PendingHandoffsUsecase>()(projectId);
    final list = result.getOrNull() ?? const [];
    return list.isEmpty ? null : list.first;
  }

  Future<List<RuleEntity>> _requiredRules(IdVO projectId) async {
    final result = await injector.get<RulesForTaskUsecase>()(
      RulesForTaskQuery(projectId: projectId, limit: 30),
    );
    final list = result.getOrNull() ?? const [];
    return list.where((r) => r.severity == RuleSeverity.mandatory).take(8).toList();
  }

  Future<List<MemoryEntity>> _topMemories(IdVO projectId) async {
    final result = await injector.get<TopMemoriesUsecase>()(projectId, limit: 5);
    return result.getOrNull() ?? const [];
  }

  static String _snippet(String text) {
    final flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return flat.length <= _snippetChars ? flat : '${flat.substring(0, _snippetChars)}…';
  }
}
