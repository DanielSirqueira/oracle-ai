import 'package:oracle_core/oracle_core.dart';

import '../entities/rfc_entity.dart';
import '../errors/rfc_failure.dart';
import '../repositories/rfc_repository.dart';

/// Lists RFCs still open for input, scope union, most-specific first.
abstract interface class ListOpenRfcsUsecase {
  AsyncResultDart<List<RfcEntity>, RfcFailure> call({
    IdVO? organizationId,
    IdVO? projectId,
    IdVO? moduleId,
    int limit,
  });
}

class ListOpenRfcsUsecaseImpl implements ListOpenRfcsUsecase {
  final RfcRepository _repository;
  const ListOpenRfcsUsecaseImpl(this._repository);

  @override
  AsyncResultDart<List<RfcEntity>, RfcFailure> call({
    IdVO? organizationId,
    IdVO? projectId,
    IdVO? moduleId,
    int limit = 50,
  }) =>
      _repository.listOpenRfcs(
        organizationId: organizationId,
        projectId: projectId,
        moduleId: moduleId,
        limit: limit,
      );
}
