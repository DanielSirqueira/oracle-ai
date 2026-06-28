import 'package:oracle_core/oracle_core.dart';

import '../entities/message_entity.dart';
import '../errors/capture_failure.dart';
import '../repositories/capture_repository.dart';

/// The agent's work (messages) carrying out a single request, oldest first.
abstract interface class RequestMessagesUsecase {
  AsyncResultDart<List<MessageEntity>, CaptureFailure> call(IdVO requestId, {int limit});
}

class RequestMessagesUsecaseImpl implements RequestMessagesUsecase {
  final CaptureRepository _repository;
  const RequestMessagesUsecaseImpl(this._repository);

  @override
  AsyncResultDart<List<MessageEntity>, CaptureFailure> call(IdVO requestId, {int limit = 100}) =>
      _repository.requestMessages(requestId, limit: limit);
}
