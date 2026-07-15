import 'package:oracle_core/oracle_core.dart';

import '../../domain/dtos/rfc_bundle.dart';
import '../../domain/dtos/rfc_comment_neighbor.dart';
import '../../domain/dtos/rfc_status_report.dart';
import '../../domain/entities/rfc_comment_entity.dart';
import '../../domain/entities/rfc_entity.dart';
import '../../domain/entities/rfc_evidence_entity.dart';
import '../../domain/entities/rfc_section_entity.dart';
import '../../domain/entities/rfc_version_entity.dart';

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
}
