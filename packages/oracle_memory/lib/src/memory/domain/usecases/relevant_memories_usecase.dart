import 'package:oracle_core/oracle_core.dart';

import '../entities/memory_entity.dart';
import '../errors/memory_failure.dart';
import '../repositories/memory_repository.dart';

/// Embeds a prompt and returns the memories within [maxDistance] cosine
/// distance — the gated recall for the per-turn UserPromptSubmit injection.
/// Returns empty (no injection) when embedding fails or nothing is close enough.
abstract interface class RelevantMemoriesUsecase {
  AsyncResultDart<List<MemoryEntity>, MemoryFailure> call(
    IdVO projectId,
    String prompt, {
    double maxDistance,
    int limit,
  });
}

class RelevantMemoriesUsecaseImpl implements RelevantMemoriesUsecase {
  final MemoryRepository _repository;
  final Embedder _embedder;
  const RelevantMemoriesUsecaseImpl(this._repository, this._embedder);

  @override
  AsyncResultDart<List<MemoryEntity>, MemoryFailure> call(
    IdVO projectId,
    String prompt, {
    double maxDistance = 0.6,
    int limit = 3,
  }) async {
    if (prompt.trim().isEmpty) return const Success([]);
    List<double> vector;
    try {
      vector = await _embedder.embed(prompt);
    } catch (_) {
      return const Success([]); // no embedding → no recall (never block the agent)
    }
    return _repository.relevantMemories(projectId, vector, maxDistance, limit);
  }
}
