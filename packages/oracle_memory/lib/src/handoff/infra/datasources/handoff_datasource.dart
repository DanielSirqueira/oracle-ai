import 'package:oracle_core/oracle_core.dart';

import '../../domain/entities/handoff_entity.dart';

abstract interface class HandoffDatasource {
  Future<HandoffEntity> beginHandoff(HandoffEntity handoff);

  Future<List<HandoffEntity>> pendingHandoffs(IdVO projectId);

  /// Full handoff history for a project (all statuses), newest first.
  Future<List<HandoffEntity>> recentHandoffs(IdVO projectId, {int limit});

  Future<HandoffEntity> acceptHandoff(IdVO id);
}
