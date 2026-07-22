import 'package:oracle_core/oracle_core.dart';

import '../entities/task_entity.dart';
import '../enums/task_status.dart';
import '../errors/flow_failure.dart';
import '../repositories/flow_repository.dart';

/// Updates a task's status, priority and/or description.
abstract interface class UpdateTaskUsecase {
  AsyncResultDart<TaskEntity, FlowFailure> call(
    IdVO id, {
    TaskStatus? status,
    int? priority,
    String? description,
  });
}

class UpdateTaskUsecaseImpl implements UpdateTaskUsecase {
  final FlowRepository _repository;
  const UpdateTaskUsecaseImpl(this._repository);

  @override
  AsyncResultDart<TaskEntity, FlowFailure> call(
    IdVO id, {
    TaskStatus? status,
    int? priority,
    String? description,
  }) {
    return _repository.updateTask(
      id,
      status: status,
      priority: priority,
      description: description,
    );
  }
}
