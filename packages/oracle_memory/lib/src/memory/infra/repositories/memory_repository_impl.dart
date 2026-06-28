import 'package:oracle_core/oracle_core.dart';

import '../../domain/dtos/filters/memory_search_filter.dart';
import '../../domain/dtos/memory_search_result.dart';
import '../../domain/entities/memory_entity.dart';
import '../../domain/errors/memory_failure.dart';
import '../../domain/repositories/memory_repository.dart';
import '../datasources/memory_datasource.dart';

class MemoryRepositoryImpl implements MemoryRepository {
  final MemoryDatasource _datasource;
  const MemoryRepositoryImpl({required MemoryDatasource datasource}) : _datasource = datasource;

  @override
  AsyncResultDart<MemoryEntity, MemoryFailure> saveMemory(MemoryEntity memory) async {
    try {
      return Success(await _datasource.saveMemory(memory));
    } on MemoryFailure catch (failure) {
      return Failure(failure);
    }
  }

  @override
  AsyncResultDart<MemoryEntity, MemoryFailure> getMemoryById(IdVO id) async {
    try {
      return Success(await _datasource.getMemoryById(id));
    } on MemoryFailure catch (failure) {
      return Failure(failure);
    }
  }

  @override
  AsyncResultDart<List<MemorySearchResult>, MemoryFailure> searchMemories(
    MemorySearchFilter filter,
  ) async {
    try {
      return Success(await _datasource.searchMemories(filter));
    } on MemoryFailure catch (failure) {
      return Failure(failure);
    }
  }

  @override
  AsyncResultDart<List<MemoryEntity>, MemoryFailure> topMemories(IdVO projectId, int limit) async {
    try {
      return Success(await _datasource.topMemories(projectId, limit));
    } on MemoryFailure catch (failure) {
      return Failure(failure);
    }
  }

  @override
  AsyncResultDart<List<MemoryEntity>, MemoryFailure> relevantMemories(
    IdVO projectId,
    List<double> queryEmbedding,
    double maxDistance,
    int limit,
  ) async {
    try {
      return Success(
          await _datasource.relevantMemories(projectId, queryEmbedding, maxDistance, limit));
    } on MemoryFailure catch (failure) {
      return Failure(failure);
    }
  }

  @override
  AsyncResultDart<MemoryEntity, MemoryFailure> forgetMemory(
    IdVO id, {
    String? reason,
    bool hard = false,
  }) async {
    try {
      return Success(await _datasource.forgetMemory(id, reason: reason, hard: hard));
    } on MemoryFailure catch (failure) {
      return Failure(failure);
    }
  }
}
