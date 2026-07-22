import 'package:oracle_core/oracle_core.dart';

import '../dtos/flow_graph.dart';
import '../errors/flow_failure.dart';
import '../repositories/flow_repository.dart';

/// The full definition (graph) of a process, by id or by key + scope.
abstract interface class GetFlowUsecase {
  AsyncResultDart<FlowGraph, FlowFailure> call({
    IdVO? id,
    String? key,
    IdVO? organizationId,
    IdVO? projectId,
    IdVO? moduleId,
  });
}

class GetFlowUsecaseImpl implements GetFlowUsecase {
  final FlowRepository _repository;
  const GetFlowUsecaseImpl(this._repository);

  @override
  AsyncResultDart<FlowGraph, FlowFailure> call({
    IdVO? id,
    String? key,
    IdVO? organizationId,
    IdVO? projectId,
    IdVO? moduleId,
  }) {
    if (id != null && id.isNotEmpty) return _repository.getFlow(id);
    if (key != null && key.isNotEmpty) {
      return _repository.getFlowByKey(
        organizationId: organizationId,
        projectId: projectId,
        moduleId: moduleId,
        key: key,
      );
    }
    return Future.value(
      Failure(
        ValidatedFieldFlowFailure(
          errorMessage: 'id or key required',
          stackTrace: StackTrace.current,
          fields: const [
            FieldSystemFailure(field: 'id', message: 'id or key required'),
          ],
        ),
      ),
    );
  }
}
