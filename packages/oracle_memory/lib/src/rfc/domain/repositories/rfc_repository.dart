import 'package:oracle_core/oracle_core.dart';

import '../dtos/rfc_bundle.dart';
import '../dtos/rfc_comment_neighbor.dart';
import '../dtos/rfc_status_report.dart';
import '../entities/rfc_comment_entity.dart';
import '../entities/rfc_entity.dart';
import '../entities/rfc_evidence_entity.dart';
import '../entities/rfc_section_entity.dart';
import '../entities/rfc_version_entity.dart';
import '../errors/rfc_failure.dart';

/// Business contract for multi-agent RFC review.
abstract interface class RfcRepository {
  /// Creates the RFC header, its v1 [version] and [sections] in one savepoint,
  /// sets `current_version_id` and moves the status to `open_for_comments`.
  /// Returns the RFC with id/timestamps.
  AsyncResultDart<RfcEntity, RfcFailure> openRfc(
    RfcEntity rfc,
    RfcVersionEntity version,
    List<RfcSectionEntity> sections,
  );

  /// The RFC plus its latest version, that version's sections and its open
  /// comments, assembled in one read.
  AsyncResultDart<RfcBundle, RfcFailure> getRfc(IdVO id);

  /// RFCs still gathering input (`open_for_comments` / `in_review`), most
  /// specific scope first. The scope union mirrors memory search: a module
  /// listing also surfaces its project's and organization's RFCs.
  AsyncResultDart<List<RfcEntity>, RfcFailure> listOpenRfcs({
    IdVO? organizationId,
    IdVO? projectId,
    IdVO? moduleId,
    int limit,
  });

  /// Appends a structured finding to an RFC. Returns it with id/timestamps.
  AsyncResultDart<RfcCommentEntity, RfcFailure> addComment(RfcCommentEntity comment);

  /// Attaches verifiable evidence to a finding (the anti-hallucination core).
  /// The datasource RESOLVES the reference: an `oracle_entity` citation counts
  /// only if the row it names exists — otherwise `resolved` stays false and the
  /// finding is not verified. Returns the evidence with id/resolved/timestamps.
  AsyncResultDart<RfcEvidenceEntity, RfcFailure> addEvidence(RfcEvidenceEntity evidence);

  /// Latest comments of [rfcId] near [embedding] (same model), excluding
  /// [excludeId] — the add-time near-duplicate signal. Non-critical: a failed
  /// lookup degrades to an empty list, so it is a plain optional, not a Result.
  Future<List<RfcCommentNeighbor>> nearestComments({
    required IdVO rfcId,
    required List<double> embedding,
    required String embeddingModel,
    IdVO? excludeId,
    double maxDistance,
    int limit,
  });

  /// Retires the prior latest version (is_latest=false), inserts the new
  /// [version] and its [sections], and bumps the RFC's `round_count` +
  /// `current_version_id`. Returns the new version with id/timestamps.
  AsyncResultDart<RfcVersionEntity, RfcFailure> reviseRfc(
    RfcVersionEntity version,
    List<RfcSectionEntity> sections,
  );

  /// Completion snapshot of an RFC (open blockers + required-section coverage).
  AsyncResultDart<RfcStatusReport, RfcFailure> rfcStatus(IdVO rfcId);
}
