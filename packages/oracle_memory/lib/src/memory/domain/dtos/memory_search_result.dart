import '../entities/memory_entity.dart';

/// A memory plus its fused relevance [score] from a search.
class MemorySearchResult {
  final MemoryEntity memory;

  /// Fused score (e.g. RRF). Higher is more relevant.
  final double score;

  const MemorySearchResult({required this.memory, required this.score});
}
