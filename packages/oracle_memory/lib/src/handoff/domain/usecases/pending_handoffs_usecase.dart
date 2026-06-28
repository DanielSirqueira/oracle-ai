import 'package:oracle_core/oracle_core.dart';

import '../entities/handoff_entity.dart';
import '../errors/handoff_failure.dart';
import '../repositories/handoff_repository.dart';

abstract interface class PendingHandoffsUsecase {
  AsyncResultDart<List<HandoffEntity>, HandoffFailure> call(IdVO projectId);
}

class PendingHandoffsUsecaseImpl implements PendingHandoffsUsecase {
  final HandoffRepository _repository;
  const PendingHandoffsUsecaseImpl(this._repository);

  @override
  AsyncResultDart<List<HandoffEntity>, HandoffFailure> call(IdVO projectId) =>
      _repository.pendingHandoffs(projectId);
}
