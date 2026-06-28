/// Aggregate metrics for an experiment [label] across its sessions — the A/B
/// comparison surface (e.g. oracle-on vs baseline).
class MetricsSummary {
  final String label;
  final int sessions;
  final int inputTokens;
  final int outputTokens;
  final int cacheCreationTokens;
  final int cacheReadTokens;
  final int compactions;
  final int turns;

  const MetricsSummary({
    required this.label,
    required this.sessions,
    required this.inputTokens,
    required this.outputTokens,
    required this.cacheCreationTokens,
    required this.cacheReadTokens,
    required this.compactions,
    required this.turns,
  });

  int get totalInputTokens => inputTokens + cacheCreationTokens + cacheReadTokens;
  int get totalTokens => totalInputTokens + outputTokens;

  /// Cheap-cache fraction of input. Higher = cheaper steady state.
  double get cacheReadRatio =>
      totalInputTokens == 0 ? 0 : cacheReadTokens / totalInputTokens;

  /// The expensive event — a full summarization call. Fewer is the goal.
  double get avgCompactionsPerSession => sessions == 0 ? 0 : compactions / sessions;

  double get avgTokensPerSession => sessions == 0 ? 0 : totalTokens / sessions;
}
