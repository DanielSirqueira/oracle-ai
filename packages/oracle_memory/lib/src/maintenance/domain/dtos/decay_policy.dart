/// Tunable policy for the deterministic maintenance sweep (no LLM).
///
/// The sweep targets **consolidated memories** only — rules and architecture
/// have a deliberate lifecycle (supersede/retire by hand) and are never
/// auto-forgotten. Two independent passes:
/// - **decay**: forget memories that are stale (not accessed in [staleDays]),
///   low-value ([importance] < [minImportance]) and rarely used
///   ([access_count] < [minAccessCount]) — restricted to [eligibleTiers]
///   (episodic by default; semantic/procedural are durable knowledge).
/// - **dedup**: forget the weaker of two near-duplicate memories (cosine
///   distance < [dedupDistance]) in the same owner+kind, keeping the one with
///   higher importance (then newer).
class DecayPolicy {
  /// Memory tiers eligible for decay-forget (codes). Default: episodic only.
  final List<String> eligibleTiers;

  /// Forget if not accessed (or created) within this many days.
  final int staleDays;

  /// Forget only memories below this importance.
  final double minImportance;

  /// Forget only memories accessed fewer than this many times.
  final int minAccessCount;

  /// Cosine distance under which two memories count as near-duplicates.
  final double dedupDistance;

  final bool runDecay;
  final bool runDedup;

  /// When true, report what *would* be forgotten without changing anything.
  final bool dryRun;

  /// Safety cap on how many memories a single sweep may retire (per pass).
  final int limit;

  const DecayPolicy({
    this.eligibleTiers = const ['episodic'],
    this.staleDays = 30,
    this.minImportance = 0.3,
    this.minAccessCount = 2,
    this.dedupDistance = 0.05,
    this.runDecay = true,
    this.runDedup = true,
    this.dryRun = false,
    this.limit = 500,
  });
}
