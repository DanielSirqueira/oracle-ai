/// Read-only health check over the memory bank — surfaces actionable blind
/// spots without changing anything.
class LintReport {
  /// Latest memories with no embedding — invisible to semantic recall.
  final int memoriesWithoutEmbedding;

  /// Latest rules with no embedding — invisible to semantic rule search.
  final int rulesWithoutEmbedding;

  /// Old user demands the agent never produced any work for (request with zero
  /// messages, past its grace window) — a capture leak / dropped turn.
  final int requestsWithoutMessages;

  /// Embedded rows (memories/rules/architectures/requests) whose `embedding_model`
  /// differs from the currently configured model. The semantic legs filter by
  /// model, so these vectors are invisible to recall until re-embedded — the
  /// silent-recall symptom of a provider/model switch. Run oracle_maintenance_reembed.
  final int vectorsWithStaleModel;

  /// The model the stale-model check compared against (the configured embedder).
  final String currentModel;

  const LintReport({
    required this.memoriesWithoutEmbedding,
    required this.rulesWithoutEmbedding,
    required this.requestsWithoutMessages,
    required this.vectorsWithStaleModel,
    required this.currentModel,
  });

  /// True when nothing needs attention.
  bool get clean =>
      memoriesWithoutEmbedding == 0 &&
      rulesWithoutEmbedding == 0 &&
      requestsWithoutMessages == 0 &&
      vectorsWithStaleModel == 0;
}
