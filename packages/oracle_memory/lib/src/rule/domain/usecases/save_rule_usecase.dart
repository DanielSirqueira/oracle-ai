import 'package:collection/collection.dart';
import 'package:oracle_core/oracle_core.dart';

import '../entities/rule_entity.dart';
import '../errors/rule_failure.dart';
import '../repositories/rule_repository.dart';

const _listEquality = ListEquality<String>();

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

    // Idempotent no-op: when a rule with this key already exists and nothing
    // changed, return it without embedding or writing — no wasted embedding
    // tokens and no pointless new version on a repeated save.
    if (rule.embedding == null) {
      final existing = await _repository.currentByKey(
        productId: rule.productId,
        projectId: rule.projectId,
        key: rule.key.trim(),
      );
      if (existing != null && _sameContent(existing, rule)) {
        return Success(existing);
      }
    }

    if (rule.embedding == null) {
      try {
        final vector = await _embedder.embed('${rule.title.value}\n${rule.content.value}');
        rule = rule.copyWith(embedding: vector, embeddingModel: _embedder.model);
      } catch (_) {/* save without embedding */}
    }

    return _repository.saveRule(rule);
  }

  /// True when the incoming rule carries the same user-visible content as the
  /// stored one (fields that change the embedding or the rendered rule).
  static bool _sameContent(RuleEntity a, RuleEntity b) =>
      a.title.value == b.title.value &&
      a.content.value == b.content.value &&
      a.scope == b.scope &&
      a.severity == b.severity &&
      a.priority == b.priority &&
      _listEquality.equals(a.tags, b.tags);
}
