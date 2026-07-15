import 'package:oracle_core/oracle_core.dart';

import '../entities/rfc_decision_entity.dart';
import '../errors/rfc_failure.dart';
import '../repositories/rfc_repository.dart';

/// Records an important/product decision on an RFC. Product decisions carry the
/// human gate via [RfcDecisionEntity.humanApproved].
///
/// Guardrails: the decision must name an RFC and a non-blank question.
abstract interface class RecordDecisionUsecase {
  AsyncResultDart<RfcDecisionEntity, RfcFailure> call(RfcDecisionEntity decision);
}

class RecordDecisionUsecaseImpl implements RecordDecisionUsecase {
  final RfcRepository _repository;
  const RecordDecisionUsecaseImpl(this._repository);

  @override
  AsyncResultDart<RfcDecisionEntity, RfcFailure> call(RfcDecisionEntity decision) async {
    final fields = <FieldSystemFailure>[];
    if (decision.rfcId.isEmpty) {
      fields.add(const FieldSystemFailure(field: 'rfcId', message: 'Required'));
    }
    if (decision.question.isBlank) {
      fields.add(const FieldSystemFailure(field: 'question', message: 'Required'));
    }
    if (fields.isNotEmpty) {
      return Failure(ValidatedFieldRfcFailure(
        errorMessage: 'Invalid decision',
        stackTrace: StackTrace.current,
        fields: fields,
      ));
    }

    return _repository.recordDecision(decision);
  }
}
