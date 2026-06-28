/// A single memory affected (or candidate, in dry-run) by the sweep.
class MaintenanceItem {
  final String id;
  final String title;
  const MaintenanceItem({required this.id, required this.title});
}

/// Outcome of a maintenance run. In [dryRun], the lists are the *candidates*
/// that would be forgotten; otherwise they are the memories actually retired.
class MaintenanceReport {
  final bool dryRun;

  /// Memories forgotten (or candidate) by the decay pass.
  final List<MaintenanceItem> decayed;

  /// Memories forgotten (or candidate) by the dedup pass.
  final List<MaintenanceItem> deduped;

  const MaintenanceReport({
    required this.dryRun,
    this.decayed = const [],
    this.deduped = const [],
  });

  int get decayedCount => decayed.length;
  int get dedupedCount => deduped.length;
  int get totalCount => decayedCount + dedupedCount;
}
