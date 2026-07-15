import 'package:collection/collection.dart';
import 'package:oracle_core/oracle_core.dart';

import '../enums/rfc_comment_type.dart';
import '../enums/rfc_severity.dart';

const _listEquality = ListEquality<Object?>();

/// A structured technical finding on an RFC — NOT chat. A typed finding with a
/// severity, anchored to a section (strong anchor via [sectionId]), and
/// vectorized for dedup/novelty (reuses the nearestByEmbedding mechanic).
/// [verified] marks whether at least one resolvable evidence exists; an
/// unverified critical is demoted and does NOT gate completion.
class RfcCommentEntity {
  final IdVO id;
  final IdVO rfcId;
  final IdVO versionId;
  final IdVO? sectionId;
  final String authorAgent;

  /// architect|dba|security|backend|frontend|ux|infra|qa|domain|critic|consolidator.
  final String? reviewerRole;
  final RfcCommentType type;
  final RfcSeverity severity;

  /// data|api|ui|sec|infra|domain|...
  final String? area;
  final String? anchorQuote;
  final TextVO problem;
  final TextVO rationale;
  final TextVO impact;
  final TextVO proposedSolution;

  /// [{option, tradeoff}] alternatives.
  final List<Map<String, dynamic>> alternatives;

  /// 0..1 self-declared, calibrated a posteriori.
  final double confidence;

  /// open|accepted|rejected|deferred|duplicate|superseded|resolved.
  final String status;
  final IdVO? parentCommentId;
  final bool verified;
  final int roundNo;
  final List<double>? embedding;
  final String? embeddingModel;
  final bool isLatest;
  final IdVO? supersedes;
  final DateTime? createdAt;

  const RfcCommentEntity({
    required this.id,
    required this.rfcId,
    required this.versionId,
    this.sectionId,
    this.authorAgent = 'claude-code',
    this.reviewerRole,
    this.type = RfcCommentType.improvement,
    this.severity = RfcSeverity.info,
    this.area,
    this.anchorQuote,
    required this.problem,
    required this.rationale,
    required this.impact,
    required this.proposedSolution,
    this.alternatives = const [],
    this.confidence = 0.5,
    this.status = 'open',
    this.parentCommentId,
    this.verified = false,
    this.roundNo = 0,
    this.embedding,
    this.embeddingModel,
    this.isLatest = true,
    this.supersedes,
    this.createdAt,
  });

  RfcCommentEntity copyWith({
    IdVO? id,
    IdVO? rfcId,
    IdVO? versionId,
    IdVO? sectionId,
    String? authorAgent,
    String? reviewerRole,
    RfcCommentType? type,
    RfcSeverity? severity,
    String? area,
    String? anchorQuote,
    TextVO? problem,
    TextVO? rationale,
    TextVO? impact,
    TextVO? proposedSolution,
    List<Map<String, dynamic>>? alternatives,
    double? confidence,
    String? status,
    IdVO? parentCommentId,
    bool? verified,
    int? roundNo,
    List<double>? embedding,
    String? embeddingModel,
    bool? isLatest,
    IdVO? supersedes,
    DateTime? createdAt,
  }) {
    return RfcCommentEntity(
      id: id ?? this.id,
      rfcId: rfcId ?? this.rfcId,
      versionId: versionId ?? this.versionId,
      sectionId: sectionId ?? this.sectionId,
      authorAgent: authorAgent ?? this.authorAgent,
      reviewerRole: reviewerRole ?? this.reviewerRole,
      type: type ?? this.type,
      severity: severity ?? this.severity,
      area: area ?? this.area,
      anchorQuote: anchorQuote ?? this.anchorQuote,
      problem: problem ?? this.problem,
      rationale: rationale ?? this.rationale,
      impact: impact ?? this.impact,
      proposedSolution: proposedSolution ?? this.proposedSolution,
      alternatives: alternatives ?? this.alternatives,
      confidence: confidence ?? this.confidence,
      status: status ?? this.status,
      parentCommentId: parentCommentId ?? this.parentCommentId,
      verified: verified ?? this.verified,
      roundNo: roundNo ?? this.roundNo,
      embedding: embedding ?? this.embedding,
      embeddingModel: embeddingModel ?? this.embeddingModel,
      isLatest: isLatest ?? this.isLatest,
      supersedes: supersedes ?? this.supersedes,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RfcCommentEntity &&
        other.id == id &&
        other.rfcId == rfcId &&
        other.versionId == versionId &&
        other.sectionId == sectionId &&
        other.authorAgent == authorAgent &&
        other.reviewerRole == reviewerRole &&
        other.type == type &&
        other.severity == severity &&
        other.area == area &&
        other.anchorQuote == anchorQuote &&
        other.problem == problem &&
        other.rationale == rationale &&
        other.impact == impact &&
        other.proposedSolution == proposedSolution &&
        _listEquality.equals(other.alternatives, alternatives) &&
        other.confidence == confidence &&
        other.status == status &&
        other.parentCommentId == parentCommentId &&
        other.verified == verified &&
        other.roundNo == roundNo &&
        _listEquality.equals(other.embedding, embedding) &&
        other.embeddingModel == embeddingModel &&
        other.isLatest == isLatest &&
        other.supersedes == supersedes;
  }

  @override
  int get hashCode => Object.hashAll([
        id,
        rfcId,
        versionId,
        sectionId,
        authorAgent,
        reviewerRole,
        type,
        severity,
        area,
        anchorQuote,
        problem,
        rationale,
        impact,
        proposedSolution,
        confidence,
        status,
        parentCommentId,
        verified,
        roundNo,
        embeddingModel,
        isLatest,
        supersedes,
      ]);
}
