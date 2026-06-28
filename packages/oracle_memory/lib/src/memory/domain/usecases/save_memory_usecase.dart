import 'package:oracle_core/oracle_core.dart';

import '../entities/memory_entity.dart';
import '../errors/memory_failure.dart';
import '../repositories/memory_repository.dart';

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

    // Generate the embedding from the content when not provided (best-effort:
    // a failing embedder degrades to keyword-only search, never blocks the save).
    if (memory.embedding == null) {
      try {
        final vector = await _embedder.embed('${memory.title.value}\n${memory.body.value}');
        memory = memory.copyWith(embedding: vector, embeddingModel: _embedder.model);
      } catch (_) {/* save without embedding */}
    }

    return _repository.saveMemory(memory);
  }
}
