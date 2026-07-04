import 'package:collection/collection.dart';
import 'package:oracle_core/oracle_core.dart';

import '../entities/skill_entity.dart';
import '../errors/skill_failure.dart';
import '../repositories/skill_repository.dart';

const _listEquality = ListEquality<String>();

/// Saves a skill after validation.
///
/// A skill may be GLOBAL (no product/project) — the shared-library common case
/// — so scope is not required, unlike rules/memories.
abstract interface class SaveSkillUsecase {
  AsyncResultDart<SkillEntity, SkillFailure> call(SkillEntity skill);
}

class SaveSkillUsecaseImpl implements SaveSkillUsecase {
  final SkillRepository _repository;
  final Embedder _embedder;
  const SaveSkillUsecaseImpl(this._repository, this._embedder);

  @override
  AsyncResultDart<SkillEntity, SkillFailure> call(SkillEntity skill) async {
    final fields = <FieldSystemFailure>[];
    if (skill.key.trim().isEmpty) {
      fields.add(const FieldSystemFailure(field: 'key', message: 'Required'));
    }
    if (skill.name.isBlank) {
      fields.add(const FieldSystemFailure(field: 'name', message: 'Required'));
    }
    if (skill.description.isBlank) {
      fields.add(const FieldSystemFailure(field: 'description', message: 'Required'));
    }
    if (skill.content.isBlank) {
      fields.add(const FieldSystemFailure(field: 'content', message: 'Required'));
    }
    if (fields.isNotEmpty) {
      return Failure(ValidatedFieldSkillFailure(
        errorMessage: 'Invalid skill',
        stackTrace: StackTrace.current,
        fields: fields,
      ));
    }

    // Idempotent no-op: when this key already exists with identical content,
    // return it without embedding or writing — no wasted embedding tokens and
    // no pointless new version on a repeated save.
    if (skill.embedding == null) {
      final existing = await _repository.currentByKey(
        productId: skill.productId,
        projectId: skill.projectId,
        key: skill.key.trim(),
      );
      if (existing != null && _sameContent(existing, skill)) {
        return Success(existing);
      }
    }

    if (skill.embedding == null) {
      try {
        final vector = await _embedder
            .embed('${skill.name.value}\n${skill.description.value}\n${skill.content.value}');
        skill = skill.copyWith(embedding: vector, embeddingModel: _embedder.model);
      } catch (_) {/* save without embedding */}
    }

    return _repository.saveSkill(skill);
  }

  /// True when the incoming skill carries the same user-visible content as the
  /// stored one (fields that change the embedding or the rendered skill).
  static bool _sameContent(SkillEntity a, SkillEntity b) =>
      a.name.value == b.name.value &&
      a.description.value == b.description.value &&
      a.content.value == b.content.value &&
      _listEquality.equals(a.tags, b.tags);
}
