import 'package:oracle_core/oracle_core.dart';

import '../entities/rule_entity.dart';
import '../errors/rule_failure.dart';
import '../repositories/rule_repository.dart';

/// Saves a development rule after validation.
abstract interface class SaveRuleUsecase {
  AsyncResultDart<RuleEntity, RuleFailure> call(RuleEntity rule);
}

class SaveRuleUsecaseImpl implements SaveRuleUsecase {
  final RuleRepository _repository;
  final Embedder _embedder;
  const SaveRuleUsecaseImpl(this._repository, this._embedder);

  @override
  AsyncResultDart<RuleEntity, RuleFailure> call(RuleEntity rule) async {
    final fields = <FieldSystemFailure>[];
    if (rule.key.trim().isEmpty) {
      fields.add(const FieldSystemFailure(field: 'key', message: 'Required'));
    }
    if (rule.scope.trim().isEmpty) {
      fields.add(const FieldSystemFailure(field: 'scope', message: 'Required'));
    }
    if (rule.title.isBlank) {
      fields.add(const FieldSystemFailure(field: 'title', message: 'Required'));
    }
    if (rule.content.isBlank) {
      fields.add(const FieldSystemFailure(field: 'content', message: 'Required'));
    }
    if (rule.productId == null && rule.projectId == null) {
      fields.add(const FieldSystemFailure(field: 'scope', message: 'Product or project required'));
    }
    if (fields.isNotEmpty) {
      return Failure(ValidatedFieldRuleFailure(
        errorMessage: 'Invalid rule',
        stackTrace: StackTrace.current,
        fields: fields,
      ));
    }

    if (rule.embedding == null) {
      try {
        final vector = await _embedder.embed('${rule.title.value}\n${rule.content.value}');
        rule = rule.copyWith(embedding: vector, embeddingModel: _embedder.model);
      } catch (_) {/* save without embedding */}
    }

    return _repository.saveRule(rule);
  }
}
