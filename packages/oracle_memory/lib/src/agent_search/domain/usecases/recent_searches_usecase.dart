import 'package:oracle_core/oracle_core.dart';

import '../entities/agent_search_entity.dart';
import '../errors/agent_search_failure.dart';
import '../repositories/agent_search_repository.dart';

/// Recent agent searches for a project — powers the Studio search-history view.
abstract interface class RecentSearchesUsecase {
  AsyncResultDart<List<AgentSearchEntity>, AgentSearchFailure> call(IdVO projectId, {int limit});
}

class RecentSearchesUsecaseImpl implements RecentSearchesUsecase {
  final AgentSearchRepository _repository;
  const RecentSearchesUsecaseImpl(this._repository);

  @override
  AsyncResultDart<List<AgentSearchEntity>, AgentSearchFailure> call(IdVO projectId,
          {int limit = 100}) =>
      _repository.recentSearches(projectId, limit: limit);
}
