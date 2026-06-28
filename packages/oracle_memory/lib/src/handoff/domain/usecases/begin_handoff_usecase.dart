import 'package:oracle_core/oracle_core.dart';

import '../entities/handoff_entity.dart';
import '../errors/handoff_failure.dart';
import '../repositories/handoff_repository.dart';

abstract interface class BeginHandoffUsecase {
  AsyncResultDart<HandoffEntity, HandoffFailure> call(HandoffEntity handoff);
}

class BeginHandoffUsecaseImpl implements BeginHandoffUsecase {
  final HandoffRepository _repository;
  const BeginHandoffUsecaseImpl(this._repository);

  @override
  AsyncResultDart<HandoffEntity, HandoffFailure> call(HandoffEntity handoff) async {
    final fields = <FieldSystemFailure>[];
    if (handoff.projectId.isEmpty) {
      fields.add(const FieldSystemFailure(field: 'projectId', message: 'Required'));
    }
    if (handoff.summary.isBlank) {
      fields.add(const FieldSystemFailure(field: 'summary', message: 'Required'));
    }
    if (fields.isNotEmpty) {
      return Failure(ValidatedFieldHandoffFailure(
        errorMessage: 'Invalid handoff',
        stackTrace: StackTrace.current,
        fields: fields,
      ));
    }
    return _repository.beginHandoff(handoff);
  }
}
