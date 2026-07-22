import 'package:oracle_core/oracle_core.dart';

/// Something a run produced (branch, commit, PR, RFC, doc, memory), recorded by
/// reference via [locator] (URL / path / id), like `rfc_comment_evidence`.
class FlowArtifactEntity {
  final IdVO id;
  final IdVO runId;
  final IdVO? runStepId;
  final String kind;
  final String locator;
  final String meta;
  final DateTime? createdAt;

  const FlowArtifactEntity({
    required this.id,
    required this.runId,
    this.runStepId,
    required this.kind,
    required this.locator,
    this.meta = '{}',
    this.createdAt,
  });

  FlowArtifactEntity copyWith({
    IdVO? id,
    IdVO? runId,
    IdVO? runStepId,
    String? kind,
    String? locator,
    String? meta,
    DateTime? createdAt,
  }) {
    return FlowArtifactEntity(
      id: id ?? this.id,
      runId: runId ?? this.runId,
      runStepId: runStepId ?? this.runStepId,
      kind: kind ?? this.kind,
      locator: locator ?? this.locator,
      meta: meta ?? this.meta,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FlowArtifactEntity &&
        other.id == id &&
        other.runId == runId &&
        other.runStepId == runStepId &&
        other.kind == kind &&
        other.locator == locator &&
        other.meta == meta;
  }

  @override
  int get hashCode => Object.hash(id, runId, runStepId, kind, locator, meta);
}
