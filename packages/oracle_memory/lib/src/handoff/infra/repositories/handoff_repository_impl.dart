import 'package:oracle_core/oracle_core.dart';

import '../../domain/entities/handoff_entity.dart';
import '../../domain/errors/handoff_failure.dart';
import '../../domain/repositories/handoff_repository.dart';
import '../datasources/handoff_datasource.dart';

class HandoffRepositoryImpl implements HandoffRepository {
  final HandoffDatasource _datasource;
  const HandoffRepositoryImpl({required HandoffDatasource datasource}) : _datasource = datasource;

  @override
  AsyncResultDart<HandoffEntity, HandoffFailure> beginHandoff(HandoffEntity handoff) async {
    try {
      return Success(await _datasource.beginHandoff(handoff));
    } on HandoffFailure catch (failure) {
      return Failure(failure);
    }
  }

  @override
  AsyncResultDart<List<HandoffEntity>, HandoffFailure> pendingHandoffs(IdVO projectId) async {
    try {
      return Success(await _datasource.pendingHandoffs(projectId));
    } on HandoffFailure catch (failure) {
      return Failure(failure);
    }
  }

  @override
  AsyncResultDart<List<HandoffEntity>, HandoffFailure> recentHandoffs(IdVO projectId,
      {int limit = 50}) async {
    try {
      return Success(await _datasource.recentHandoffs(projectId, limit: limit));
    } on HandoffFailure catch (failure) {
      return Failure(failure);
    }
  }

  @override
  AsyncResultDart<HandoffEntity, HandoffFailure> acceptHandoff(IdVO id) async {
    try {
      return Success(await _datasource.acceptHandoff(id));
    } on HandoffFailure catch (failure) {
      return Failure(failure);
    }
  }
}
