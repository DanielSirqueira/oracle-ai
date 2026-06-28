import 'package:oracle_core/oracle_core.dart';

import '../../domain/entities/handoff_entity.dart';

abstract interface class HandoffDatasource {
  Future<HandoffEntity> beginHandoff(HandoffEntity handoff);

  Future<List<HandoffEntity>> pendingHandoffs(IdVO projectId);

  Future<HandoffEntity> acceptHandoff(IdVO id);
}
