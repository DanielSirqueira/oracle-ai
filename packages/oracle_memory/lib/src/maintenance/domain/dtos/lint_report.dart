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

  const LintReport({
    required this.memoriesWithoutEmbedding,
    required this.rulesWithoutEmbedding,
    required this.requestsWithoutMessages,
  });

  /// True when nothing needs attention.
  bool get clean =>
      memoriesWithoutEmbedding == 0 && rulesWithoutEmbedding == 0 && requestsWithoutMessages == 0;
}
