import 'package:oracle_core/oracle_core.dart';

import '../entities/flow_run_context_entity.dart';
import '../errors/flow_failure.dart';
import '../repositories/flow_repository.dart';

/// Writes a key→value entry to a run's blackboard (upsert on run_id + key).
abstract interface class PutContextUsecase {
  AsyncResultDart<FlowRunContextEntity, FlowFailure> call(
    FlowRunContextEntity ctx,
  );
}

class PutContextUsecaseImpl implements PutContextUsecase {
  final FlowRepository _repository;
  const PutContextUsecaseImpl(this._repository);

  @override
  AsyncResultDart<FlowRunContextEntity, FlowFailure> call(
    FlowRunContextEntity ctx,
  ) {
    return _repository.putContext(ctx);
  }
}
