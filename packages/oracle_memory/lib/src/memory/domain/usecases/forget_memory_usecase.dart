import 'package:oracle_core/oracle_core.dart';

import '../entities/memory_entity.dart';
import '../errors/memory_failure.dart';
import '../repositories/memory_repository.dart';

/// Forgets a consolidated memory that is wrong or obsolete ("bad memory is
/// worse than no memory"). Soft by default (dropped from recall, kept for audit
/// with a [reason]); [hard] purges it entirely.
abstract interface class ForgetMemoryUsecase {
  AsyncResultDart<MemoryEntity, MemoryFailure> call(IdVO id, {String? reason, bool hard});
}

class ForgetMemoryUsecaseImpl implements ForgetMemoryUsecase {
  final MemoryRepository _repository;
  const ForgetMemoryUsecaseImpl(this._repository);

  @override
  AsyncResultDart<MemoryEntity, MemoryFailure> call(
    IdVO id, {
    String? reason,
    bool hard = false,
  }) async {
    if (id.value.trim().isEmpty) {
      return Failure(ValidatedFieldMemoryFailure(
        errorMessage: 'Invalid memory id',
        stackTrace: StackTrace.current,
        fields: const [FieldSystemFailure(field: 'id', message: 'Required')],
      ));
    }
    return _repository.forgetMemory(id, reason: reason, hard: hard);
  }
}
