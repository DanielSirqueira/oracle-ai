/// Outcome of a re-embed pass: how many stale/missing-embedding rows were found,
/// how many were successfully re-embedded, and how many failed (e.g. the embedder
/// erroring mid-run). `remaining` hints whether another pass is needed.
class ReembedReport {
  final String model;
  final int scanned;
  final int reembedded;
  final int failed;

  const ReembedReport({
    required this.model,
    required this.scanned,
    required this.reembedded,
    required this.failed,
  });

  /// True when a run hit its limit and more targets may remain.
  bool get mayHaveMore => scanned > 0 && failed < scanned && reembedded + failed == scanned;
}
