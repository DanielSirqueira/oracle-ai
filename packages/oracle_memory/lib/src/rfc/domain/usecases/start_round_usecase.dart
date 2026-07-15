import 'package:oracle_core/oracle_core.dart';

import '../entities/rfc_round_entity.dart';
import '../errors/rfc_failure.dart';
import '../repositories/rfc_repository.dart';

/// Opens a review round on an RFC. A roundNo of 0 (or less) is auto-numbered to
/// the next round for the RFC.
abstract interface class StartRoundUsecase {
  AsyncResultDart<RfcRoundEntity, RfcFailure> call(RfcRoundEntity round);
}

class StartRoundUsecaseImpl implements StartRoundUsecase {
  final RfcRepository _repository;
  const StartRoundUsecaseImpl(this._repository);

  @override
  AsyncResultDart<RfcRoundEntity, RfcFailure> call(RfcRoundEntity round) async {
    return _repository.startRound(round);
  }
}
