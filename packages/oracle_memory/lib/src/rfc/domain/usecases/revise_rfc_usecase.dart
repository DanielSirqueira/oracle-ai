import 'package:oracle_core/oracle_core.dart';

import '../entities/rfc_section_entity.dart';
import '../entities/rfc_version_entity.dart';
import '../errors/rfc_failure.dart';
import '../repositories/rfc_repository.dart';

/// Consolidates a new RFC version (a review round). The summary is embedded
/// best-effort before the version and its sections are persisted.
abstract interface class ReviseRfcUsecase {
  AsyncResultDart<RfcVersionEntity, RfcFailure> call(
    RfcVersionEntity version,
    List<RfcSectionEntity> sections,
  );
}

class ReviseRfcUsecaseImpl implements ReviseRfcUsecase {
  final RfcRepository _repository;
  final Embedder _embedder;
  const ReviseRfcUsecaseImpl(this._repository, this._embedder);

  @override
  AsyncResultDart<RfcVersionEntity, RfcFailure> call(
    RfcVersionEntity version,
    List<RfcSectionEntity> sections,
  ) async {
    if (version.embedding == null && version.summary.isNotBlank) {
      try {
        final vector = await _embedder.embed(version.summary.value);
        version = version.copyWith(embedding: vector, embeddingModel: _embedder.model);
      } catch (_) {/* revise without embedding */}
    }
    return _repository.reviseRfc(version, sections);
  }
}
