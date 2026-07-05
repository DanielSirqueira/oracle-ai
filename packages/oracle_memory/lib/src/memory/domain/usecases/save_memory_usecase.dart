import 'package:collection/collection.dart';
import 'package:oracle_core/oracle_core.dart';

import '../entities/memory_entity.dart';
import '../errors/memory_failure.dart';
import '../repositories/memory_repository.dart';

const _listEquality = ListEquality<String>();

/// Persists a consolidated memory after validation.
///
/// Guardrails (anti-junk): non-blank title/body and a scope (product or project)
/// are required — refusing to write trivial/unscoped memory.
abstract interface class SaveMemoryUsecase {
  AsyncResultDart<MemoryEntity, MemoryFailure> call(MemoryEntity memory);
}

class SaveMemoryUsecaseImpl implements SaveMemoryUsecase {
  final MemoryRepository _repository;
  final Embedder _embedder;
  const SaveMemoryUsecaseImpl(this._repository, this._embedder);

  /// Keyless near-duplicate guard: a save without a `key` that lands within this
  /// cosine distance of an existing same-owner/same-kind memory supersedes it in
  /// place instead of appending a duplicate. Deliberately tight (only genuine
  /// near-identical text), matching the maintenance dedup sweep threshold.
  static const _keylessDedupDistance = 0.05;

  @override
  AsyncResultDart<MemoryEntity, MemoryFailure> call(MemoryEntity memory) async {
    final fields = <FieldSystemFailure>[];
    if (memory.title.isBlank) {
      fields.add(const FieldSystemFailure(field: 'title', message: 'Required'));
    }
    if (memory.body.isBlank) {
      fields.add(const FieldSystemFailure(field: 'body', message: 'Required'));
    }
    if (memory.productId == null && memory.projectId == null) {
      fields.add(const FieldSystemFailure(field: 'scope', message: 'Product or project required'));
    }
    if (fields.isNotEmpty) {
      return Failure(ValidatedFieldMemoryFailure(
        errorMessage: 'Invalid memory',
        stackTrace: StackTrace.current,
        fields: fields,
      ));
    }

    // Idempotent no-op: when a keyed memory already exists with identical
    // content, return it without embedding or writing — this is what stops an
    // unchanged re-save from spending embedding tokens and churning a new
    // version. (Only for keyed memories; keyless saves keep append-only.)
    final key = memory.key?.trim();
    if (key != null && key.isNotEmpty && memory.embedding == null) {
      final existing = await _repository.currentByKey(
        productId: memory.productId,
        projectId: memory.projectId,
        key: key,
      );
      if (existing != null && _sameContent(existing, memory)) {
        return Success(existing);
      }
    }

    // Generate the embedding from the content when not provided (best-effort:
    // a failing embedder degrades to keyword-only search, never blocks the save).
    if (memory.embedding == null) {
      try {
        final vector = await _embedder.embed('${memory.title.value}\n${memory.body.value}');
        memory = memory.copyWith(embedding: vector, embeddingModel: _embedder.model);
      } catch (_) {/* save without embedding */}
    }

    // Keyless near-duplicate guard. Without a `key`, a memory would append a new
    // row on every save; when the incoming memory is near-identical to an
    // existing one in the same owner AND kind, supersede that one in place so the
    // agent stops piling up duplicates. Keyed saves already supersede by key; an
    // explicit `supersedes` is respected as-is. Best-effort — never blocks a save.
    if ((key == null || key.isEmpty) &&
        memory.supersedes == null &&
        memory.embedding != null &&
        memory.embeddingModel != null) {
      try {
        final near = await _repository.nearestByEmbedding(
          productId: memory.productId,
          projectId: memory.projectId,
          embedding: memory.embedding!,
          embeddingModel: memory.embeddingModel!,
          maxDistance: _keylessDedupDistance,
          limit: 5,
        );
        final twin = near.firstWhereOrNull((n) => n.memory.kind == memory.kind);
        if (twin != null) memory = memory.copyWith(supersedes: twin.memory.id);
      } catch (_) {/* fall back to a plain insert */}
    }

    return _repository.saveMemory(memory);
  }

  /// True when the incoming memory carries the same user-visible content as the
  /// stored one — the fields that would change the embedding or the rendered
  /// memory. (id/embedding/timestamps are ignored.)
  static bool _sameContent(MemoryEntity a, MemoryEntity b) =>
      a.title.value == b.title.value &&
      a.body.value == b.body.value &&
      a.kind == b.kind &&
      a.tier == b.tier &&
      a.importance == b.importance &&
      _listEquality.equals(a.tags, b.tags);
}
