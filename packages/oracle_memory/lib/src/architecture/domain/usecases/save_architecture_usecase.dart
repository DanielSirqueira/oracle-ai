import 'package:oracle_core/oracle_core.dart';

import '../entities/architecture_entity.dart';
import '../errors/architecture_failure.dart';
import '../repositories/architecture_repository.dart';

abstract interface class SaveArchitectureUsecase {
  AsyncResultDart<ArchitectureEntity, ArchitectureFailure> call(ArchitectureEntity architecture);
}

class SaveArchitectureUsecaseImpl implements SaveArchitectureUsecase {
  final ArchitectureRepository _repository;
  final Embedder _embedder;
  const SaveArchitectureUsecaseImpl(this._repository, this._embedder);

  @override
  AsyncResultDart<ArchitectureEntity, ArchitectureFailure> call(ArchitectureEntity architecture) async {
    final fields = <FieldSystemFailure>[];
    if (architecture.projectId.isEmpty) {
      fields.add(const FieldSystemFailure(field: 'projectId', message: 'Required'));
    }
    if (architecture.area.trim().isEmpty) {
      fields.add(const FieldSystemFailure(field: 'area', message: 'Required'));
    }
    if (architecture.content.isBlank) {
      fields.add(const FieldSystemFailure(field: 'content', message: 'Required'));
    }
    if (fields.isNotEmpty) {
      return Failure(ValidatedFieldArchitectureFailure(
        errorMessage: 'Invalid architecture',
        stackTrace: StackTrace.current,
        fields: fields,
      ));
    }

    // Idempotent no-op: an architecture page is keyed by (project, area); when
    // the current page for this area has identical content, return it without
    // embedding or writing — no wasted embedding tokens, no pointless version.
    if (architecture.embedding == null) {
      final existing =
          (await _repository.getByArea(architecture.projectId, architecture.area.trim())).getOrNull();
      if (existing != null && existing.content.value == architecture.content.value) {
        return Success(existing);
      }
    }

    if (architecture.embedding == null) {
      try {
        final vector = await _embedder.embed('${architecture.area}\n${architecture.content.value}');
        architecture = architecture.copyWith(embedding: vector, embeddingModel: _embedder.model);
      } catch (_) {/* save without embedding */}
    }

    return _repository.saveArchitecture(architecture);
  }
}
