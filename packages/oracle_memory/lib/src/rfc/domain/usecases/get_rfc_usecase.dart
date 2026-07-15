import 'package:oracle_core/oracle_core.dart';

import '../dtos/rfc_bundle.dart';
import '../errors/rfc_failure.dart';
import '../repositories/rfc_repository.dart';

/// Fetches a fully assembled RFC (header + latest version + sections + open
/// comments) by its id.
abstract interface class GetRfcUsecase {
  AsyncResultDart<RfcBundle, RfcFailure> call(IdVO id);
}

class GetRfcUsecaseImpl implements GetRfcUsecase {
  final RfcRepository _repository;
  const GetRfcUsecaseImpl(this._repository);

  @override
  AsyncResultDart<RfcBundle, RfcFailure> call(IdVO id) => _repository.getRfc(id);
}
