import 'package:oracle_core/oracle_core.dart';

import '../entities/rfc_resolution_entity.dart';
import '../errors/rfc_failure.dart';
import '../repositories/rfc_repository.dart';

/// Records a finding's outcome and stamps the comment's own status with the
/// decision.
///
/// Guardrails: the resolution must name a comment and the [decision] must be one
/// of accepted|rejected|deferred|duplicate.
abstract interface class ResolveCommentUsecase {
  AsyncResultDart<RfcResolutionEntity, RfcFailure> call(RfcResolutionEntity resolution);
}

class ResolveCommentUsecaseImpl implements ResolveCommentUsecase {
  final RfcRepository _repository;
  const ResolveCommentUsecaseImpl(this._repository);

  static const _decisions = {'accepted', 'rejected', 'deferred', 'duplicate'};

  @override
  AsyncResultDart<RfcResolutionEntity, RfcFailure> call(RfcResolutionEntity resolution) async {
    final fields = <FieldSystemFailure>[];
    if (resolution.commentId.isEmpty) {
      fields.add(const FieldSystemFailure(field: 'commentId', message: 'Required'));
    }
    if (!_decisions.contains(resolution.decision)) {
      fields.add(const FieldSystemFailure(
          field: 'decision', message: 'Must be one of accepted|rejected|deferred|duplicate'));
    }
    if (fields.isNotEmpty) {
      return Failure(ValidatedFieldRfcFailure(
        errorMessage: 'Invalid resolution',
        stackTrace: StackTrace.current,
        fields: fields,
      ));
    }

    return _repository.resolveComment(resolution);
  }
}
