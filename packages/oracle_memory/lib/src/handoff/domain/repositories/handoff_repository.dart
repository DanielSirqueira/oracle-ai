import 'package:oracle_core/oracle_core.dart';

import '../entities/handoff_entity.dart';
import '../errors/handoff_failure.dart';

abstract interface class HandoffRepository {
  /// Writes a new open handoff.
  AsyncResultDart<HandoffEntity, HandoffFailure> beginHandoff(HandoffEntity handoff);

  /// The most recent open handoffs for a project (0 or 1), to inject on
  /// SessionStart.
  AsyncResultDart<List<HandoffEntity>, HandoffFailure> pendingHandoffs(IdVO projectId);

  /// Full handoff history for a project (all statuses), newest first — for the
  /// Studio handoffs view.
  AsyncResultDart<List<HandoffEntity>, HandoffFailure> recentHandoffs(IdVO projectId, {int limit});

  /// Marks a handoff accepted.
  AsyncResultDart<HandoffEntity, HandoffFailure> acceptHandoff(IdVO id);
}
