import 'package:oracle_core/oracle_core.dart';

import '../entities/rfc_round_entity.dart';
import '../errors/rfc_failure.dart';
import '../repositories/rfc_repository.dart';

/// Closes a review round: the repository computes the round's new criticals/
/// majors and its novelty score, then stamps `ended_at`.
abstract interface class CloseRoundUsecase {
  AsyncResultDart<RfcRoundEntity, RfcFailure> call({required IdVO rfcId, required int roundNo});
}

class CloseRoundUsecaseImpl implements CloseRoundUsecase {
  final RfcRepository _repository;
  const CloseRoundUsecaseImpl(this._repository);

  @override
  AsyncResultDart<RfcRoundEntity, RfcFailure> call({
    required IdVO rfcId,
    required int roundNo,
  }) async {
    return _repository.closeRound(rfcId, roundNo);
  }
}
