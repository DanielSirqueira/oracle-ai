import 'package:oracle_core/oracle_core.dart';

import '../entities/task_entity.dart';
import '../errors/flow_failure.dart';
import '../repositories/flow_repository.dart';

/// Lists tasks in the backlog (scope union), optionally filtered by status and a
/// text search over title/description.
abstract interface class ListTasksUsecase {
  AsyncResultDart<List<TaskEntity>, FlowFailure> call({
    IdVO? organizationId,
    IdVO? projectId,
    IdVO? moduleId,
    String? status,
    String? search,
    int? limit,
  });
}

class ListTasksUsecaseImpl implements ListTasksUsecase {
  final FlowRepository _repository;
  const ListTasksUsecaseImpl(this._repository);

  @override
  AsyncResultDart<List<TaskEntity>, FlowFailure> call({
    IdVO? organizationId,
    IdVO? projectId,
    IdVO? moduleId,
    String? status,
    String? search,
    int? limit,
  }) {
    return _repository.listTasks(
      organizationId: organizationId,
      projectId: projectId,
      moduleId: moduleId,
      status: status,
      search: search,
      limit: limit,
    );
  }
}
