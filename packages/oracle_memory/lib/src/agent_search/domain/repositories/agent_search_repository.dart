import 'package:oracle_core/oracle_core.dart';

import '../entities/agent_search_entity.dart';
import '../errors/agent_search_failure.dart';

abstract interface class AgentSearchRepository {
  AsyncResultDart<IdVO, AgentSearchFailure> logSearch(AgentSearchEntity search);

  AsyncResultDart<List<AgentSearchEntity>, AgentSearchFailure> recentSearches(
    IdVO projectId, {
    int limit,
  });
}
