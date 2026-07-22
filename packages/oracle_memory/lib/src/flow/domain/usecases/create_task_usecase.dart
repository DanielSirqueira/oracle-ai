import 'package:oracle_core/oracle_core.dart';

import '../entities/task_entity.dart';
import '../errors/flow_failure.dart';
import '../repositories/flow_repository.dart';

/// Creates a task in the backlog after validation.
///
/// Guardrails: a non-blank title and a scope (organization, project or module)
/// are required. The title+description is embedded best-effort (a failing
/// embedder degrades to keyword-only dedup, never blocks the create).
abstract interface class CreateTaskUsecase {
  AsyncResultDart<TaskEntity, FlowFailure> call(TaskEntity task);
}

class CreateTaskUsecaseImpl implements CreateTaskUsecase {
  final FlowRepository _repository;
  final Embedder _embedder;
  const CreateTaskUsecaseImpl(this._repository, this._embedder);

  @override
  AsyncResultDart<TaskEntity, FlowFailure> call(TaskEntity task) async {
    final fields = <FieldSystemFailure>[];
    if (task.title.isBlank) {
      fields.add(const FieldSystemFailure(field: 'title', message: 'Required'));
    }
    if (task.organizationId == null &&
        task.projectId == null &&
        task.moduleId == null) {
      fields.add(
        const FieldSystemFailure(
          field: 'scope',
          message: 'Organization, project or module required',
        ),
      );
    }
    if (fields.isNotEmpty) {
      return Failure(
        ValidatedFieldFlowFailure(
          errorMessage: 'Invalid task',
          stackTrace: StackTrace.current,
          fields: fields,
        ),
      );
    }

    if (task.embedding == null) {
      final text = '${task.title.value} ${task.description}'.trim();
      if (text.isNotEmpty) {
        try {
          final vector = await _embedder.embed(text);
          task = task.copyWith(
            embedding: vector,
            embeddingModel: _embedder.model,
          );
        } catch (_) {
          /* create without embedding */
        }
      }
    }

    return _repository.createTask(task);
  }
}
