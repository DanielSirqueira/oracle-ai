import 'package:oracle_core/oracle_core.dart';

import '../entities/architecture_entity.dart';
import '../errors/architecture_failure.dart';
import '../repositories/architecture_repository.dart';

abstract interface class GetArchitectureByAreaUsecase {
  AsyncResultDart<ArchitectureEntity, ArchitectureFailure> call({
    IdVO? organizationId,
    IdVO? projectId,
    IdVO? moduleId,
    required String area,
  });
}

class GetArchitectureByAreaUsecaseImpl implements GetArchitectureByAreaUsecase {
  final ArchitectureRepository _repository;
  const GetArchitectureByAreaUsecaseImpl(this._repository);

  @override
  AsyncResultDart<ArchitectureEntity, ArchitectureFailure> call({
    IdVO? organizationId,
    IdVO? projectId,
    IdVO? moduleId,
    required String area,
  }) =>
      _repository.getByArea(
          organizationId: organizationId, projectId: projectId, moduleId: moduleId, area: area);
}
