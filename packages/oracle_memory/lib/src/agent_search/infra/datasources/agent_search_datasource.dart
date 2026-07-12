import 'package:oracle_core/oracle_core.dart';

import '../../domain/entities/agent_search_entity.dart';

abstract interface class AgentSearchDatasource {
  Future<void> logSearch(AgentSearchEntity search);

  /// Recent searches whose scope names [projectId] (newest first).
  Future<List<AgentSearchEntity>> recentSearches(IdVO projectId, {int limit});
}
