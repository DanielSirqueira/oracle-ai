import 'package:oracle_core/oracle_core.dart';

import 'domain/repositories/agent_search_repository.dart';
import 'domain/usecases/log_search_usecase.dart';
import 'domain/usecases/recent_searches_usecase.dart';
import 'external/datasources/database/database_agent_search_datasource.dart';
import 'infra/datasources/agent_search_datasource.dart';
import 'infra/repositories/agent_search_repository_impl.dart';

/// DI bindings for the agent search-history feature.
class AgentSearchModule extends Module {
  @override
  void binds(AutoInjector i) {
    i
      ..addLazySingleton<AgentSearchDatasource>(DatabaseAgentSearchDatasource.new)
      ..addLazySingleton<AgentSearchRepository>(AgentSearchRepositoryImpl.new)
      ..addLazySingleton<LogSearchUsecase>(LogSearchUsecaseImpl.new)
      ..addLazySingleton<RecentSearchesUsecase>(RecentSearchesUsecaseImpl.new);
  }
}
