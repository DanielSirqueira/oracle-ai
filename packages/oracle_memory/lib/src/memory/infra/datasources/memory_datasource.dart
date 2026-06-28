import 'package:oracle_core/oracle_core.dart';

import '../../domain/dtos/filters/memory_search_filter.dart';
import '../../domain/dtos/memory_search_result.dart';
import '../../domain/entities/memory_entity.dart';

/// Data-access contract for consolidated memory. Implementations **throw** typed
/// failures; the repository wraps them in a `ResultDart`.
abstract interface class MemoryDatasource {
  Future<MemoryEntity> saveMemory(MemoryEntity memory);

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
    int limit,
  );

  /// Soft-forgets a memory (dropped from recall, kept for audit) or, when
  /// [hard], permanently deletes it. Returns the affected memory.
  Future<MemoryEntity> forgetMemory(IdVO id, {String? reason, bool hard});
}
