import 'package:oracle_core/oracle_core.dart';

import '../entities/rfc_evidence_entity.dart';
import '../errors/rfc_failure.dart';
import '../repositories/rfc_repository.dart';

/// Attaches verifiable evidence to a finding — the anti-hallucination core.
///
/// Guardrails: the evidence must name a comment and a non-blank kind. The
/// repository then RESOLVES the reference (an `oracle_entity` citation counts
/// only if the row it names exists); a resolved evidence flips the finding to
/// `verified`. No embedding.
abstract interface class AddEvidenceUsecase {
  AsyncResultDart<RfcEvidenceEntity, RfcFailure> call(RfcEvidenceEntity evidence);
}

class AddEvidenceUsecaseImpl implements AddEvidenceUsecase {
  final RfcRepository _repository;
  const AddEvidenceUsecaseImpl(this._repository);

  @override
  AsyncResultDart<RfcEvidenceEntity, RfcFailure> call(RfcEvidenceEntity evidence) async {
    final fields = <FieldSystemFailure>[];
    if (evidence.commentId.isEmpty) {
      fields.add(const FieldSystemFailure(field: 'commentId', message: 'Required'));
    }
    if (evidence.kind.trim().isEmpty) {
      fields.add(const FieldSystemFailure(field: 'kind', message: 'Required'));
    }
    if (fields.isNotEmpty) {
      return Failure(ValidatedFieldRfcFailure(
        errorMessage: 'Invalid evidence',
        stackTrace: StackTrace.current,
        fields: fields,
      ));
    }

    return _repository.addEvidence(evidence);
  }
}
