import 'package:oracle_core/oracle_core.dart';

import '../entities/handoff_entity.dart';
import '../errors/handoff_failure.dart';
import '../repositories/handoff_repository.dart';

/// Full handoff history for a project (all statuses), newest first — powers the
/// Studio handoffs view (the pending path stays `PendingHandoffsUsecase`).
abstract interface class RecentHandoffsUsecase {
  AsyncResultDart<List<HandoffEntity>, HandoffFailure> call(IdVO projectId, {int limit});
}

class RecentHandoffsUsecaseImpl implements RecentHandoffsUsecase {
  final HandoffRepository _repository;
  const RecentHandoffsUsecaseImpl(this._repository);

  @override
  AsyncResultDart<List<HandoffEntity>, HandoffFailure> call(IdVO projectId, {int limit = 50}) =>
      _repository.recentHandoffs(projectId, limit: limit);
}
