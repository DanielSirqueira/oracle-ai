import 'package:oracle_core/oracle_core.dart';

import '../dtos/step_context.dart';
import '../errors/flow_failure.dart';
import '../repositories/flow_repository.dart';

/// The bundle a step's agent pulls at start: the task, the run, the step
/// definition, the blackboard context, prior step reports and artifacts.
abstract interface class StepContextUsecase {
  AsyncResultDart<StepContext, FlowFailure> call(IdVO runStepId);
}

class StepContextUsecaseImpl implements StepContextUsecase {
  final FlowRepository _repository;
  const StepContextUsecaseImpl(this._repository);

  @override
  AsyncResultDart<StepContext, FlowFailure> call(IdVO runStepId) {
    return _repository.stepContext(runStepId);
  }
}
