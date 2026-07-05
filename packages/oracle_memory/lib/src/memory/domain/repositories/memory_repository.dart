import 'package:oracle_core/oracle_core.dart';

import '../dtos/filters/memory_search_filter.dart';
import '../dtos/memory_neighbor.dart';
import '../dtos/memory_search_result.dart';
import '../entities/memory_entity.dart';
import '../errors/memory_failure.dart';

/// Business contract for consolidated memory.
abstract interface class MemoryRepository {
  /// Persists a memory (agent-driven consolidation). Returns it with id/timestamps.
  AsyncResultDart<MemoryEntity, MemoryFailure> saveMemory(MemoryEntity memory);

  /// The current (is_latest) memory with [key] in the given owner, or null when
  /// none exists. Used to short-circuit an unchanged re-save before embedding.
  /// A failed lookup degrades to null (the caller just performs a normal save),
  /// so it stays a plain optional rather than a Result.
  Future<MemoryEntity?> currentByKey({
    IdVO? productId,
    IdVO? projectId,
    required String key,
  });

  /// Latest memories near [embedding] (same owner + model), excluding
  /// [excludeId] — the save-time near-duplicate signal. Non-critical: a failed
  /// lookup degrades to an empty list, so it is a plain optional, not a Result.
  Future<List<MemoryNeighbor>> nearestByEmbedding({
    IdVO? productId,
    IdVO? projectId,
    required List<double> embedding,
    required String embeddingModel,
    IdVO? excludeId,
    double maxDistance,
    int limit,
  });

  AsyncResultDart<MemoryEntity, MemoryFailure> getMemoryById(IdVO id);

  /// Hybrid search (vector + full-text, fused with RRF).
  AsyncResultDart<List<MemorySearchResult>, MemoryFailure> searchMemories(
    MemorySearchFilter filter,
  );

  /// Top latest memories of a project by importance (then recency).
  AsyncResultDart<List<MemoryEntity>, MemoryFailure> topMemories(IdVO projectId, int limit);

  /// Semantic nearest neighbours within [maxDistance] cosine distance.
  AsyncResultDart<List<MemoryEntity>, MemoryFailure> relevantMemories(
    IdVO projectId,
    List<double> queryEmbedding,
    double maxDistance,
    int limit, {
    String? queryModel,
  });

  /// Forgets a memory: soft by default (dropped from recall, kept for audit),
  /// or permanently removed when [hard] is true.
  AsyncResultDart<MemoryEntity, MemoryFailure> forgetMemory(
    IdVO id, {
    String? reason,
    bool hard,
  });
}
