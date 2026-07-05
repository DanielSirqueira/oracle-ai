import 'package:oracle_core/oracle_core.dart';

import '../dtos/filters/rule_search_filter.dart';
import '../dtos/rule_search_result.dart';
import '../errors/rule_failure.dart';
import '../repositories/rule_repository.dart';

/// Hybrid search over development rules.
abstract interface class SearchRulesUsecase {
  AsyncResultDart<List<RuleSearchResult>, RuleFailure> call(RuleSearchFilter filter);
}

class SearchRulesUsecaseImpl implements SearchRulesUsecase {
  final RuleRepository _repository;
  final Embedder _embedder;
  const SearchRulesUsecaseImpl(this._repository, this._embedder);

  @override
  AsyncResultDart<List<RuleSearchResult>, RuleFailure> call(RuleSearchFilter filter) async {
    if (filter.queryEmbedding == null &&
        filter.query.trim().isNotEmpty &&
        filter.mode != RuleSearchMode.keyword) {
      try {
        filter = filter.copyWith(
          queryEmbedding: await _embedder.embed(filter.query),
          queryModel: _embedder.model,
        );
      } catch (_) {/* fall back to keyword */}
    }
    return _repository.searchRules(filter);
  }
}
