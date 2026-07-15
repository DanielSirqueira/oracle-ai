import 'package:oracle_core/oracle_core.dart';

import '../../domain/dtos/rfc_bundle.dart';
import '../../domain/dtos/rfc_comment_neighbor.dart';
import '../../domain/dtos/rfc_status_report.dart';
import '../../domain/entities/rfc_comment_entity.dart';
import '../../domain/entities/rfc_decision_entity.dart';
import '../../domain/entities/rfc_entity.dart';
import '../../domain/entities/rfc_evidence_entity.dart';
import '../../domain/entities/rfc_relation_entity.dart';
import '../../domain/entities/rfc_resolution_entity.dart';
import '../../domain/entities/rfc_round_entity.dart';
import '../../domain/entities/rfc_section_entity.dart';
import '../../domain/entities/rfc_version_entity.dart';
import '../../domain/enums/rfc_status.dart';

/// Data-access contract for multi-agent RFC review. Implementations **throw**
/// typed failures; the repository wraps them in a `ResultDart`.
abstract interface class RfcDatasource {
  /// Creates the RFC + v1 + sections in one savepoint, wiring
  /// `current_version_id` and moving status to `open_for_comments`.
  Future<RfcEntity> openRfc(
    RfcEntity rfc,
    RfcVersionEntity version,
    List<RfcSectionEntity> sections,
  );

  /// The RFC plus its latest version, sections and open comments.
  Future<RfcBundle> getRfc(IdVO id);

  /// RFCs still open for input, scope union, most-specific first.
  Future<List<RfcEntity>> listOpenRfcs({
    IdVO? organizationId,
    IdVO? projectId,
    IdVO? moduleId,
    int? limit,
  });

  /// All RFCs in scope regardless of status, scope union, most-specific first.
  Future<List<RfcEntity>> listRfcs({
    IdVO? organizationId,
    IdVO? projectId,
    IdVO? moduleId,
    int? limit,
  });

  Future<RfcCommentEntity> addComment(RfcCommentEntity comment);

  /// Attaches evidence to a finding, resolving an `oracle_entity` reference
  /// against the cited table. Sets `verified` on the comment when resolved.
  Future<RfcEvidenceEntity> addEvidence(RfcEvidenceEntity evidence);

  /// Latest comments of [rfcId] within [maxDistance] cosine distance of
  /// [embedding] (same model only), excluding [excludeId]. Backs the add-time
  /// near-duplicate signal. Empty when nothing is close enough.
  Future<List<RfcCommentNeighbor>> nearestComments({
    required IdVO rfcId,
    required List<double> embedding,
    required String embeddingModel,
    IdVO? excludeId,
    double? maxDistance,
    int? limit,
  });

  /// Retires the prior latest version, inserts the new version + sections, and
  /// bumps the RFC round_count + current_version_id.
  Future<RfcVersionEntity> reviseRfc(
    RfcVersionEntity version,
    List<RfcSectionEntity> sections,
  );

  Future<RfcStatusReport> rfcStatus(IdVO rfcId);

  /// Adds a typed edge to the argumentation graph between two findings.
  Future<RfcRelationEntity> addRelation(RfcRelationEntity relation);

  /// Records a finding's outcome and, in one savepoint, stamps the comment's own
  /// status with the resolution's decision.
  Future<RfcResolutionEntity> resolveComment(RfcResolutionEntity resolution);

  /// Opens a review round, computing the next round number when roundNo <= 0.
  Future<RfcRoundEntity> startRound(RfcRoundEntity round);

  /// Closes round [roundNo] of [rfcId]: computes new criticals/majors + novelty
  /// score over the round's latest comments and stamps `ended_at`.
  Future<RfcRoundEntity> closeRound(IdVO rfcId, int roundNo);

  /// Records an important/product decision on an RFC.
  Future<RfcDecisionEntity> recordDecision(RfcDecisionEntity decision);

  /// Moves the RFC to [status], bumping `updated_at`.
  Future<RfcEntity> setStatus(IdVO rfcId, RfcStatus status);

  /// The decisions recorded on [rfcId], oldest first.
  Future<List<RfcDecisionEntity>> listDecisions(IdVO rfcId);

  /// Links a recorded decision to the memory it was written back to.
  Future<void> setDecisionMemory(IdVO decisionId, IdVO memoryId);
}
