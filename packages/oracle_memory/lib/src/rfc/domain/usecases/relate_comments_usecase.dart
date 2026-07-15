import 'package:oracle_core/oracle_core.dart';

import '../entities/rfc_relation_entity.dart';
import '../errors/rfc_failure.dart';
import '../repositories/rfc_repository.dart';

/// Adds a typed edge to the argumentation graph between two findings.
///
/// Guardrails: both endpoints must be named, the [RfcRelationEntity.reason] must
/// be non-blank (a refutation is as demanding as an assertion), and the relation
/// must be one of supports|refutes|duplicates|supersedes|refines|depends_on.
abstract interface class RelateCommentsUsecase {
  AsyncResultDart<RfcRelationEntity, RfcFailure> call(RfcRelationEntity relation);
}

class RelateCommentsUsecaseImpl implements RelateCommentsUsecase {
  final RfcRepository _repository;
  const RelateCommentsUsecaseImpl(this._repository);

  static const _relations = {
    'supports',
    'refutes',
    'duplicates',
    'supersedes',
    'refines',
    'depends_on',
  };

  @override
  AsyncResultDart<RfcRelationEntity, RfcFailure> call(RfcRelationEntity relation) async {
    final fields = <FieldSystemFailure>[];
    if (relation.fromComment.isEmpty) {
      fields.add(const FieldSystemFailure(field: 'fromComment', message: 'Required'));
    }
    if (relation.toComment.isEmpty) {
      fields.add(const FieldSystemFailure(field: 'toComment', message: 'Required'));
    }
    if (relation.reason.isBlank) {
      fields.add(const FieldSystemFailure(field: 'reason', message: 'Required'));
    }
    if (!_relations.contains(relation.relation)) {
      fields.add(const FieldSystemFailure(
          field: 'relation',
          message: 'Must be one of supports|refutes|duplicates|supersedes|refines|depends_on'));
    }
    if (fields.isNotEmpty) {
      return Failure(ValidatedFieldRfcFailure(
        errorMessage: 'Invalid relation',
        stackTrace: StackTrace.current,
        fields: fields,
      ));
    }

    return _repository.addRelation(relation);
  }
}
