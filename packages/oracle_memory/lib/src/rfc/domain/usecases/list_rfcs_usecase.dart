import 'package:oracle_core/oracle_core.dart';

import '../entities/rfc_entity.dart';
import '../errors/rfc_failure.dart';
import '../repositories/rfc_repository.dart';

/// Lists all RFCs in scope regardless of status (console/management view),
/// scope union, most-specific first.
abstract interface class ListRfcsUsecase {
  AsyncResultDart<List<RfcEntity>, RfcFailure> call({
    IdVO? organizationId,
    IdVO? projectId,
    IdVO? moduleId,
    int limit,
  });
}

class ListRfcsUsecaseImpl implements ListRfcsUsecase {
  final RfcRepository _repository;
  const ListRfcsUsecaseImpl(this._repository);

  @override
  AsyncResultDart<List<RfcEntity>, RfcFailure> call({
    IdVO? organizationId,
    IdVO? projectId,
    IdVO? moduleId,
    int limit = 100,
  }) =>
      _repository.listRfcs(
        organizationId: organizationId,
        projectId: projectId,
        moduleId: moduleId,
        limit: limit,
      );
}
