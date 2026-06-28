import 'package:oracle_core/oracle_core.dart';

import '../entities/request_entity.dart';
import '../errors/capture_failure.dart';
import '../repositories/capture_repository.dart';

/// The user demands (requests) of a session, newest first.
abstract interface class SessionRequestsUsecase {
  AsyncResultDart<List<RequestEntity>, CaptureFailure> call(IdVO sessionId, {int limit});
}

class SessionRequestsUsecaseImpl implements SessionRequestsUsecase {
  final CaptureRepository _repository;
  const SessionRequestsUsecaseImpl(this._repository);

  @override
  AsyncResultDart<List<RequestEntity>, CaptureFailure> call(IdVO sessionId, {int limit = 50}) =>
      _repository.sessionRequests(sessionId, limit: limit);
}
