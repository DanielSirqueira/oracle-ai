import 'package:oracle_core/oracle_core.dart';

import '../dtos/filters/skill_search_filter.dart';
import '../dtos/skill_search_result.dart';
import '../errors/skill_failure.dart';
import '../repositories/skill_repository.dart';

/// Hybrid search over the skill library — how an agent finds the right skill
/// for the task at hand ("by context"). Embeds the query best-effort; a failing
/// embedder degrades to keyword-only search.
abstract interface class SearchSkillsUsecase {
  AsyncResultDart<List<SkillSearchResult>, SkillFailure> call(SkillSearchFilter filter);
}

class SearchSkillsUsecaseImpl implements SearchSkillsUsecase {
  final SkillRepository _repository;
  final Embedder _embedder;
  const SearchSkillsUsecaseImpl(this._repository, this._embedder);

  @override
  AsyncResultDart<List<SkillSearchResult>, SkillFailure> call(SkillSearchFilter filter) async {
    if (filter.queryEmbedding == null && filter.query.trim().isNotEmpty) {
      try {
        final vector = await _embedder.embed(filter.query.trim());
        filter = filter.copyWith(queryEmbedding: vector, queryModel: _embedder.model);
      } catch (_) {/* keyword-only */}
    }
    return _repository.searchSkills(filter);
  }
}
