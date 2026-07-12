import 'package:oracle_core/oracle_core.dart';

import '../../domain/entities/agent_search_entity.dart';
import '../../domain/errors/agent_search_failure.dart';
import '../../domain/repositories/agent_search_repository.dart';
import '../datasources/agent_search_datasource.dart';

class AgentSearchRepositoryImpl implements AgentSearchRepository {
  final AgentSearchDatasource _datasource;
  const AgentSearchRepositoryImpl({required AgentSearchDatasource datasource})
      : _datasource = datasource;

  @override
  AsyncResultDart<IdVO, AgentSearchFailure> logSearch(AgentSearchEntity search) async {
    try {
      await _datasource.logSearch(search);
      return Success(search.id);
    } on AgentSearchFailure catch (f) {
      return Failure(f);
    }
  }

  @override
  AsyncResultDart<List<AgentSearchEntity>, AgentSearchFailure> recentSearches(
    IdVO projectId, {
    int limit = 100,
  }) async {
    try {
      return Success(await _datasource.recentSearches(projectId, limit: limit));
    } on AgentSearchFailure catch (f) {
      return Failure(f);
    }
  }
}
