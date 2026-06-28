import 'package:oracle_core/oracle_core.dart';

import '../entities/handoff_entity.dart';
import '../errors/handoff_failure.dart';
import '../repositories/handoff_repository.dart';

abstract interface class AcceptHandoffUsecase {
  AsyncResultDart<HandoffEntity, HandoffFailure> call(IdVO id);
}

class AcceptHandoffUsecaseImpl implements AcceptHandoffUsecase {
  final HandoffRepository _repository;
  const AcceptHandoffUsecaseImpl(this._repository);

  @override
  AsyncResultDart<HandoffEntity, HandoffFailure> call(IdVO id) => _repository.acceptHandoff(id);
}
