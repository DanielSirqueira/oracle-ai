import 'package:oracle_core/oracle_core.dart';

import '../entities/flow_entity.dart';
import '../errors/flow_failure.dart';
import '../repositories/flow_repository.dart';

/// Lists the available processes (latest only), scope union.
abstract interface class ListFlowsUsecase {
  AsyncResultDart<List<FlowEntity>, FlowFailure> call({
    IdVO? organizationId,
    IdVO? projectId,
    IdVO? moduleId,
    int? limit,
  });
}

class ListFlowsUsecaseImpl implements ListFlowsUsecase {
  final FlowRepository _repository;
  const ListFlowsUsecaseImpl(this._repository);

  @override
  AsyncResultDart<List<FlowEntity>, FlowFailure> call({
    IdVO? organizationId,
    IdVO? projectId,
    IdVO? moduleId,
    int? limit,
  }) {
    return _repository.listFlows(
      organizationId: organizationId,
      projectId: projectId,
      moduleId: moduleId,
      limit: limit,
    );
  }
}
