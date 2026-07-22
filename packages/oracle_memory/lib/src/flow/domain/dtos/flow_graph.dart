import '../entities/flow_edge_entity.dart';
import '../entities/flow_entity.dart';
import '../entities/flow_step_entity.dart';

/// The full definition of a process: the flow header plus its steps (nodes) and
/// edges. This is what `oracle_flow_get` returns and what a run pins by version.
class FlowGraph {
  final FlowEntity flow;
  final List<FlowStepEntity> steps;
  final List<FlowEdgeEntity> edges;

  const FlowGraph({
    required this.flow,
    this.steps = const [],
    this.edges = const [],
  });
}
