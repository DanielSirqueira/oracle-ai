import 'package:oracle_core/oracle_core.dart';

import '../entities/memory_entity.dart';
import '../errors/memory_failure.dart';
import '../repositories/memory_repository.dart';

/// Fetches a memory by its id.
abstract interface class GetMemoryByIdUsecase {
  AsyncResultDart<MemoryEntity, MemoryFailure> call(IdVO id);
}

class GetMemoryByIdUsecaseImpl implements GetMemoryByIdUsecase {
  final MemoryRepository _repository;
  const GetMemoryByIdUsecaseImpl(this._repository);

  @override
  AsyncResultDart<MemoryEntity, MemoryFailure> call(IdVO id) => _repository.getMemoryById(id);
}
