import 'package:oracle_core/oracle_core.dart';

import '../dtos/filters/memory_search_filter.dart';
import '../dtos/memory_search_result.dart';
import '../errors/memory_failure.dart';
import '../repositories/memory_repository.dart';

/// Hybrid recall over consolidated memory.
abstract interface class SearchMemoriesUsecase {
  AsyncResultDart<List<MemorySearchResult>, MemoryFailure> call(MemorySearchFilter filter);
}

class SearchMemoriesUsecaseImpl implements SearchMemoriesUsecase {
  final MemoryRepository _repository;
  final Embedder _embedder;
  const SearchMemoriesUsecaseImpl(this._repository, this._embedder);

  @override
  AsyncResultDart<List<MemorySearchResult>, MemoryFailure> call(MemorySearchFilter filter) async {
    // Embed the query when needed (so hybrid/semantic search actually works).
    if (filter.queryEmbedding == null &&
        filter.query.trim().isNotEmpty &&
        filter.mode != SearchMode.keyword) {
      try {
        filter = filter.copyWith(
          queryEmbedding: await _embedder.embed(filter.query),
          queryModel: _embedder.model,
        );
      } catch (_) {/* fall back to keyword */}
    }
    return _repository.searchMemories(filter);
  }
}
