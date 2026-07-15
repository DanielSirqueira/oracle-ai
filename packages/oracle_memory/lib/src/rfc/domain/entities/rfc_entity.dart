import 'package:oracle_core/oracle_core.dart';

import '../enums/rfc_status.dart';

/// An RFC header — a technical spec published for multi-agent review. Anchors on
/// exactly one scope level (organization / project / module), like rules and
/// memories, and points at the current version of the document. The lifecycle
/// lives in [status]; the supersession lineage (an RFC that replaces another) in
/// [supersedes].
class RfcEntity {
  final IdVO id;
  final IdVO? organizationId;
  final IdVO? projectId;
  final IdVO? moduleId;
  final TextVO title;

  /// Checklist profile: backend|frontend|fullstack|data|infra|generic.
  final String rfcType;
  final RfcStatus status;
  final IdVO? currentVersionId;
  final String authorAgent;
  final int roundCount;
  final IdVO? supersedes;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const RfcEntity({
    required this.id,
    this.organizationId,
    this.projectId,
    this.moduleId,
    required this.title,
    this.rfcType = 'generic',
    this.status = RfcStatus.draft,
    this.currentVersionId,
    this.authorAgent = 'claude-code',
    this.roundCount = 0,
    this.supersedes,
    this.createdAt,
    this.updatedAt,
  });

  factory RfcEntity.empty() => const RfcEntity(id: IdVO.empty(), title: TextVO.empty());

  RfcEntity copyWith({
    IdVO? id,
    IdVO? organizationId,
    IdVO? projectId,
    IdVO? moduleId,
    TextVO? title,
    String? rfcType,
    RfcStatus? status,
    IdVO? currentVersionId,
    String? authorAgent,
    int? roundCount,
    IdVO? supersedes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return RfcEntity(
      id: id ?? this.id,
      organizationId: organizationId ?? this.organizationId,
      projectId: projectId ?? this.projectId,
      moduleId: moduleId ?? this.moduleId,
      title: title ?? this.title,
      rfcType: rfcType ?? this.rfcType,
      status: status ?? this.status,
      currentVersionId: currentVersionId ?? this.currentVersionId,
      authorAgent: authorAgent ?? this.authorAgent,
      roundCount: roundCount ?? this.roundCount,
      supersedes: supersedes ?? this.supersedes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RfcEntity &&
        other.id == id &&
        other.organizationId == organizationId &&
        other.projectId == projectId &&
        other.moduleId == moduleId &&
        other.title == title &&
        other.rfcType == rfcType &&
        other.status == status &&
        other.currentVersionId == currentVersionId &&
        other.authorAgent == authorAgent &&
        other.roundCount == roundCount &&
        other.supersedes == supersedes;
  }

  @override
  int get hashCode => Object.hash(
        id,
        organizationId,
        projectId,
        moduleId,
        title,
        rfcType,
        status,
        currentVersionId,
        authorAgent,
        roundCount,
        supersedes,
      );
}
