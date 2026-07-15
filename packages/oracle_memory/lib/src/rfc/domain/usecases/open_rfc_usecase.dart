import 'package:oracle_core/oracle_core.dart';

import '../entities/rfc_entity.dart';
import '../entities/rfc_section_entity.dart';
import '../entities/rfc_version_entity.dart';
import '../errors/rfc_failure.dart';
import '../repositories/rfc_repository.dart';

/// Opens an RFC for review after validation.
///
/// Guardrails: a non-blank title and a scope (organization, project or module)
/// are required. The version summary is embedded best-effort (a failing embedder
/// degrades to keyword-only recall, never blocks the open).
abstract interface class OpenRfcUsecase {
  AsyncResultDart<RfcEntity, RfcFailure> call(
    RfcEntity rfc,
    RfcVersionEntity version,
    List<RfcSectionEntity> sections,
  );
}

class OpenRfcUsecaseImpl implements OpenRfcUsecase {
  final RfcRepository _repository;
  final Embedder _embedder;
  const OpenRfcUsecaseImpl(this._repository, this._embedder);

  @override
  AsyncResultDart<RfcEntity, RfcFailure> call(
    RfcEntity rfc,
    RfcVersionEntity version,
    List<RfcSectionEntity> sections,
  ) async {
    final fields = <FieldSystemFailure>[];
    if (rfc.title.isBlank) {
      fields.add(const FieldSystemFailure(field: 'title', message: 'Required'));
    }
    if (rfc.organizationId == null && rfc.projectId == null && rfc.moduleId == null) {
      fields.add(const FieldSystemFailure(
          field: 'scope', message: 'Organization, project or module required'));
    }
    if (fields.isNotEmpty) {
      return Failure(ValidatedFieldRfcFailure(
        errorMessage: 'Invalid RFC',
        stackTrace: StackTrace.current,
        fields: fields,
      ));
    }

    // Embed the version summary from its content when not provided (best-effort).
    if (version.embedding == null && version.summary.isNotBlank) {
      try {
        final vector = await _embedder.embed(version.summary.value);
        version = version.copyWith(embedding: vector, embeddingModel: _embedder.model);
      } catch (_) {/* open without embedding */}
    }

    return _repository.openRfc(rfc, version, sections);
  }
}
