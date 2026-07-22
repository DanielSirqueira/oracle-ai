import 'package:oracle_core/oracle_core.dart';

import '../entities/flow_run_entity.dart';
import '../errors/flow_failure.dart';
import '../repositories/flow_repository.dart';

/// Lists recent / active runs, optionally scoped by project and status.
abstract interface class ListFlowRunsUsecase {
  AsyncResultDart<List<FlowRunEntity>, FlowFailure> call({
    IdVO? projectId,
    String? status,
    int? limit,
  });
}

class ListFlowRunsUsecaseImpl implements ListFlowRunsUsecase {
  final FlowRepository _repository;
  const ListFlowRunsUsecaseImpl(this._repository);

  @override
  AsyncResultDart<List<FlowRunEntity>, FlowFailure> call({
    IdVO? projectId,
    String? status,
    int? limit,
  }) {
    return _repository.listRuns(
      projectId: projectId,
      status: status,
      limit: limit,
    );
  }
}
