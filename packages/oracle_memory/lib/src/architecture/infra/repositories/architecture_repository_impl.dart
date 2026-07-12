import 'package:oracle_core/oracle_core.dart';

import '../../domain/dtos/filters/architecture_search_filter.dart';
import '../../domain/dtos/architecture_search_result.dart';
import '../../domain/entities/architecture_entity.dart';
import '../../domain/errors/architecture_failure.dart';
import '../../domain/repositories/architecture_repository.dart';
import '../datasources/architecture_datasource.dart';

class ArchitectureRepositoryImpl implements ArchitectureRepository {
  final ArchitectureDatasource _datasource;
  const ArchitectureRepositoryImpl({required ArchitectureDatasource datasource})
      : _datasource = datasource;

  @override
  AsyncResultDart<ArchitectureEntity, ArchitectureFailure> saveArchitecture(
    ArchitectureEntity architecture,
  ) async {
    try {
      return Success(await _datasource.saveArchitecture(architecture));
    } on ArchitectureFailure catch (failure) {
      return Failure(failure);
    }
  }

  @override
  AsyncResultDart<ArchitectureEntity, ArchitectureFailure> getByArea({
    IdVO? organizationId,
    IdVO? projectId,
    IdVO? moduleId,
    required String area,
  }) async {
    try {
      return Success(await _datasource.getByArea(
          organizationId: organizationId, projectId: projectId, moduleId: moduleId, area: area));
    } on ArchitectureFailure catch (failure) {
      return Failure(failure);
    }
  }

  @override
  AsyncResultDart<List<ArchitectureSearchResult>, ArchitectureFailure> searchArchitecture(
    ArchitectureSearchFilter filter,
  ) async {
    try {
      return Success(await _datasource.searchArchitecture(filter));
    } on ArchitectureFailure catch (failure) {
      return Failure(failure);
    }
  }

  @override
  AsyncResultDart<ArchitectureEntity, ArchitectureFailure> retireArchitecture(
    IdVO id, {
    String? reason,
    bool hard = false,
  }) async {
    try {
      return Success(await _datasource.retireArchitecture(id, reason: reason, hard: hard));
    } on ArchitectureFailure catch (failure) {
      return Failure(failure);
    }
  }
}
