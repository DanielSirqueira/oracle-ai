import 'package:oracle_core/oracle_core.dart';

import '../entities/session_entity.dart';
import '../errors/capture_failure.dart';
import '../repositories/capture_repository.dart';

abstract interface class RecentSessionsUsecase {
  AsyncResultDart<List<SessionEntity>, CaptureFailure> call(IdVO projectId, {int limit});
}

class RecentSessionsUsecaseImpl implements RecentSessionsUsecase {
  final CaptureRepository _repository;
  const RecentSessionsUsecaseImpl(this._repository);

  @override
  AsyncResultDart<List<SessionEntity>, CaptureFailure> call(IdVO projectId, {int limit = 20}) =>
      _repository.recentSessions(projectId, limit: limit);
}
