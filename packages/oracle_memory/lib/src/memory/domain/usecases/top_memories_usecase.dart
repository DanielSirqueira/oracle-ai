import 'package:oracle_core/oracle_core.dart';

import '../entities/memory_entity.dart';
import '../errors/memory_failure.dart';
import '../repositories/memory_repository.dart';

/// Top memories of a project by importance, for a query-less session brief.
abstract interface class TopMemoriesUsecase {
  AsyncResultDart<List<MemoryEntity>, MemoryFailure> call(IdVO projectId, {int limit});
}

class TopMemoriesUsecaseImpl implements TopMemoriesUsecase {
  final MemoryRepository _repository;
  const TopMemoriesUsecaseImpl(this._repository);

  @override
  AsyncResultDart<List<MemoryEntity>, MemoryFailure> call(IdVO projectId, {int limit = 5}) =>
      _repository.topMemories(projectId, limit);
}
