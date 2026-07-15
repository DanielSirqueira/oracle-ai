import 'package:oracle_core/oracle_core.dart';

import '../dtos/rfc_bundle.dart';
import '../dtos/rfc_comment_neighbor.dart';
import '../dtos/rfc_status_report.dart';
import '../entities/rfc_comment_entity.dart';
import '../entities/rfc_decision_entity.dart';
import '../entities/rfc_entity.dart';
import '../entities/rfc_evidence_entity.dart';
import '../entities/rfc_relation_entity.dart';
import '../entities/rfc_resolution_entity.dart';
import '../entities/rfc_round_entity.dart';
import '../entities/rfc_section_entity.dart';
import '../entities/rfc_version_entity.dart';
import '../enums/rfc_status.dart';
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

  /// All RFCs in scope regardless of status (for management/console views),
  /// most specific scope first, newest first. Same scope union as [listOpenRfcs].
  AsyncResultDart<List<RfcEntity>, RfcFailure> listRfcs({
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

  /// Adds a typed edge to the argumentation graph between two findings — a
  /// refutation must be grounded too. Returns it with id/timestamps.
  AsyncResultDart<RfcRelationEntity, RfcFailure> addRelation(RfcRelationEntity relation);

  /// Records a finding's outcome and, in the same savepoint, stamps the comment's
  /// own status with the resolution's [RfcResolutionEntity.decision]. Returns the
  /// resolution with id/timestamps.
  AsyncResultDart<RfcResolutionEntity, RfcFailure> resolveComment(RfcResolutionEntity resolution);

  /// Opens a review round. When [RfcRoundEntity.roundNo] <= 0 the next round
  /// number is computed for the RFC. Returns the round with id/round_no/started_at.
  AsyncResultDart<RfcRoundEntity, RfcFailure> startRound(RfcRoundEntity round);

  /// Closes round [roundNo] of [rfcId]: computes new criticals/majors and the
  /// novelty score over the round's latest comments, stamps `ended_at`, and
  /// returns the updated round.
  AsyncResultDart<RfcRoundEntity, RfcFailure> closeRound(IdVO rfcId, int roundNo);

  /// Records an important/product decision on an RFC. Returns it with
  /// id/timestamps.
  AsyncResultDart<RfcDecisionEntity, RfcFailure> recordDecision(RfcDecisionEntity decision);

  /// Moves the RFC to [status] (`updated_at` bumped). Returns the updated header.
  AsyncResultDart<RfcEntity, RfcFailure> setStatus(IdVO rfcId, RfcStatus status);

  /// The decisions recorded on [rfcId], oldest first.
  AsyncResultDart<List<RfcDecisionEntity>, RfcFailure> listDecisions(IdVO rfcId);

  /// Links a recorded decision to the memory it was written back to (the
  /// learning write-back).
  AsyncResultDart<Unit, RfcFailure> setDecisionMemory(IdVO decisionId, IdVO memoryId);
}
