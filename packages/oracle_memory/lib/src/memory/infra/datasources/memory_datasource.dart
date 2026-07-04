import 'package:oracle_core/oracle_core.dart';

import '../../domain/dtos/filters/memory_search_filter.dart';
import '../../domain/dtos/memory_neighbor.dart';
import '../../domain/dtos/memory_search_result.dart';
import '../../domain/entities/memory_entity.dart';

/// Data-access contract for consolidated memory. Implementations **throw** typed
/// failures; the repository wraps them in a `ResultDart`.
abstract interface class MemoryDatasource {
  Future<MemoryEntity> saveMemory(MemoryEntity memory);

  /// The current (is_latest) memory with [key] in the given owner, or null.
  /// Lets a save skip re-embedding + re-inserting when nothing changed.
  Future<MemoryEntity?> currentByKey({IdVO? productId, IdVO? projectId, required String key});

  /// Latest memories in the same owner within [maxDistance] cosine distance of
  /// [embedding] (same embedding model only), excluding [excludeId]. Backs the
  /// save-time near-duplicate signal. Empty when nothing is close enough.
  Future<List<MemoryNeighbor>> nearestByEmbedding({
    IdVO? productId,
    IdVO? projectId,
    required List<double> embedding,
    required String embeddingModel,
    IdVO? excludeId,
    double? maxDistance,
    int? limit,
  });

  Future<MemoryEntity> getMemoryById(IdVO id);

  Future<List<MemorySearchResult>> searchMemories(MemorySearchFilter filter);

  /// Top latest memories of a project by importance (then recency). Used to
  /// assemble a session brief without a search query.
  Future<List<MemoryEntity>> topMemories(IdVO projectId, int limit);

  /// Semantic nearest neighbours within [maxDistance] cosine distance. Returns
  /// empty when nothing is close enough — the gate that keeps per-turn recall
  /// from injecting noise (the plain hybrid search always returns *some* ANN hit).
  Future<List<MemoryEntity>> relevantMemories(
    IdVO projectId,
    List<double> queryEmbedding,
    double maxDistance,
    int limit, {
    String? queryModel,
  });

  /// Soft-forgets a memory (dropped from recall, kept for audit) or, when
  /// [hard], permanently deletes it. Returns the affected memory.
  Future<MemoryEntity> forgetMemory(IdVO id, {String? reason, bool hard});
}
