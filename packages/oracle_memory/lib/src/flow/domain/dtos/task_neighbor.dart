import '../entities/task_entity.dart';

/// A task plus its cosine distance to a query embedding — the near-duplicate
/// signal used to warn "has this been asked before?" (like `request_search`).
class TaskNeighbor {
  final TaskEntity task;
  final double distance;

  const TaskNeighbor({required this.task, required this.distance});
}
