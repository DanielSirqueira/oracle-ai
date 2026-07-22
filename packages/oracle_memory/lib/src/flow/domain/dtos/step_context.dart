import '../entities/flow_artifact_entity.dart';
import '../entities/flow_run_context_entity.dart';
import '../entities/flow_run_entity.dart';
import '../entities/flow_run_step_entity.dart';
import '../entities/flow_step_entity.dart';
import '../entities/task_entity.dart';

/// The bundle a step's agent pulls at start (`oracle_flow_step_context`): the
/// task, the run, the step definition, the current run-step row, the blackboard
/// context, prior step reports, and the artifacts produced so far. The next agent
/// depends only on this structured context — never on a prior transcript.
class StepContext {
  final FlowRunStepEntity runStep;
  final FlowRunEntity run;
  final FlowStepEntity step;
  final TaskEntity? task;
  final List<FlowRunContextEntity> context;
  final List<FlowRunStepEntity> priorReports;
  final List<FlowArtifactEntity> artifacts;

  const StepContext({
    required this.runStep,
    required this.run,
    required this.step,
    this.task,
    this.context = const [],
    this.priorReports = const [],
    this.artifacts = const [],
  });
}
