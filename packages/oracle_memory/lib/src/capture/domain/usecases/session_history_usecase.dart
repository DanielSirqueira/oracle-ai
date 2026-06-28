import 'package:oracle_core/oracle_core.dart';

import '../entities/message_entity.dart';
import '../errors/capture_failure.dart';
import '../repositories/capture_repository.dart';

abstract interface class SessionHistoryUsecase {
  AsyncResultDart<List<MessageEntity>, CaptureFailure> call(IdVO sessionId, {int limit});
}

class SessionHistoryUsecaseImpl implements SessionHistoryUsecase {
  final CaptureRepository _repository;
  const SessionHistoryUsecaseImpl(this._repository);

  @override
  AsyncResultDart<List<MessageEntity>, CaptureFailure> call(IdVO sessionId, {int limit = 40}) =>
      _repository.sessionHistory(sessionId, limit: limit);
}
