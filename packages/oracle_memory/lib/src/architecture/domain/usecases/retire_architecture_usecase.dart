import 'package:oracle_core/oracle_core.dart';

import '../entities/architecture_entity.dart';
import '../errors/architecture_failure.dart';
import '../repositories/architecture_repository.dart';

/// Retires an architecture page that no longer reflects the project (the
/// architecture changed). Soft by default (kept for audit, with a [reason]);
/// [hard] purges it entirely.
abstract interface class RetireArchitectureUsecase {
  AsyncResultDart<ArchitectureEntity, ArchitectureFailure> call(
    IdVO id, {
    String? reason,
    bool hard,
  });
}

class RetireArchitectureUsecaseImpl implements RetireArchitectureUsecase {
  final ArchitectureRepository _repository;
  const RetireArchitectureUsecaseImpl(this._repository);

  @override
  AsyncResultDart<ArchitectureEntity, ArchitectureFailure> call(
    IdVO id, {
    String? reason,
    bool hard = false,
  }) async {
    if (id.value.trim().isEmpty) {
      return Failure(ValidatedFieldArchitectureFailure(
        errorMessage: 'Invalid architecture id',
        stackTrace: StackTrace.current,
        fields: const [FieldSystemFailure(field: 'id', message: 'Required')],
      ));
    }
    return _repository.retireArchitecture(id, reason: reason, hard: hard);
  }
}
