import '../entities/flow_artifact_entity.dart';
import '../entities/flow_run_context_entity.dart';
import '../entities/flow_run_entity.dart';
import '../entities/flow_run_event_entity.dart';
import '../entities/flow_run_step_entity.dart';

/// A read view of a run for monitoring: the run header plus its step iterations,
/// blackboard context, artifacts, and the most recent timeline events.
class FlowRunBundle {
  final FlowRunEntity run;
  final List<FlowRunStepEntity> steps;
  final List<FlowRunContextEntity> context;
  final List<FlowArtifactEntity> artifacts;
  final List<FlowRunEventEntity> events;

  const FlowRunBundle({
    required this.run,
    this.steps = const [],
    this.context = const [],
    this.artifacts = const [],
    this.events = const [],
  });
}
