import 'package:oracle_core/oracle_core.dart';

import '../dtos/rfc_status_report.dart';
import '../errors/rfc_failure.dart';
import '../repositories/rfc_repository.dart';

/// Reports an RFC's completion snapshot (open blockers + required coverage).
abstract interface class RfcStatusUsecase {
  AsyncResultDart<RfcStatusReport, RfcFailure> call(IdVO rfcId);
}

class RfcStatusUsecaseImpl implements RfcStatusUsecase {
  final RfcRepository _repository;
  const RfcStatusUsecaseImpl(this._repository);

  @override
  AsyncResultDart<RfcStatusReport, RfcFailure> call(IdVO rfcId) => _repository.rfcStatus(rfcId);
}
