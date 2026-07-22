import 'package:oracle_core/oracle_core.dart';

import '../dtos/flow_run_bundle.dart';
import '../errors/flow_failure.dart';
import '../repositories/flow_repository.dart';

/// A monitoring snapshot of a run: header + step iterations + blackboard +
/// artifacts + recent timeline events.
abstract interface class FlowRunStatusUsecase {
  AsyncResultDart<FlowRunBundle, FlowFailure> call(IdVO runId);
}

class FlowRunStatusUsecaseImpl implements FlowRunStatusUsecase {
  final FlowRepository _repository;
  const FlowRunStatusUsecaseImpl(this._repository);

  @override
  AsyncResultDart<FlowRunBundle, FlowFailure> call(IdVO runId) {
    return _repository.getRun(runId);
  }
}
