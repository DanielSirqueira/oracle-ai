import 'package:oracle_core/oracle_core.dart';

import '../dtos/filters/architecture_search_filter.dart';
import '../dtos/architecture_search_result.dart';
import '../errors/architecture_failure.dart';
import '../repositories/architecture_repository.dart';

abstract interface class SearchArchitectureUsecase {
  AsyncResultDart<List<ArchitectureSearchResult>, ArchitectureFailure> call(
    ArchitectureSearchFilter filter,
  );
}

class SearchArchitectureUsecaseImpl implements SearchArchitectureUsecase {
  final ArchitectureRepository _repository;
  final Embedder _embedder;
  const SearchArchitectureUsecaseImpl(this._repository, this._embedder);

  @override
  AsyncResultDart<List<ArchitectureSearchResult>, ArchitectureFailure> call(
    ArchitectureSearchFilter filter,
  ) async {
    if (filter.queryEmbedding == null &&
        filter.query.trim().isNotEmpty &&
        filter.mode != ArchitectureSearchMode.keyword) {
      try {
        filter = filter.copyWith(queryEmbedding: await _embedder.embed(filter.query));
      } catch (_) {/* fall back to keyword */}
    }
    return _repository.searchArchitecture(filter);
  }
}
