import 'package:oracle_core/oracle_core.dart';

import '../entities/agent_search_entity.dart';
import '../errors/agent_search_failure.dart';
import '../repositories/agent_search_repository.dart';

/// Records one agent recall (fire-and-forget on the caller side).
abstract interface class LogSearchUsecase {
  AsyncResultDart<IdVO, AgentSearchFailure> call(AgentSearchEntity search);
}

class LogSearchUsecaseImpl implements LogSearchUsecase {
  final AgentSearchRepository _repository;
  const LogSearchUsecaseImpl(this._repository);

  @override
  AsyncResultDart<IdVO, AgentSearchFailure> call(AgentSearchEntity search) =>
      _repository.logSearch(search);
}
