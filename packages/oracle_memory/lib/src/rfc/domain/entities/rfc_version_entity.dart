import 'package:collection/collection.dart';
import 'package:oracle_core/oracle_core.dart';

const _listEquality = ListEquality<Object?>();

/// A consolidation round of an RFC. Each round produces a new version
/// (is_latest / supersedes pattern, like rules and memories). The [summary] is
/// the executable substrate embedded for semantic recall (pgvector).
class RfcVersionEntity {
  final IdVO id;
  final IdVO rfcId;
  final int versionNo;
  final TextVO summary;
  final List<double>? embedding;
  final String? embeddingModel;
  final bool isLatest;
  final IdVO? supersedes;
  final String authorAgent;
  final DateTime? createdAt;

  const RfcVersionEntity({
    required this.id,
    required this.rfcId,
    required this.versionNo,
    required this.summary,
    this.embedding,
    this.embeddingModel,
    this.isLatest = true,
    this.supersedes,
    this.authorAgent = 'claude-code',
    this.createdAt,
  });

  RfcVersionEntity copyWith({
    IdVO? id,
    IdVO? rfcId,
    int? versionNo,
    TextVO? summary,
    List<double>? embedding,
    String? embeddingModel,
    bool? isLatest,
    IdVO? supersedes,
    String? authorAgent,
    DateTime? createdAt,
  }) {
    return RfcVersionEntity(
      id: id ?? this.id,
      rfcId: rfcId ?? this.rfcId,
      versionNo: versionNo ?? this.versionNo,
      summary: summary ?? this.summary,
      embedding: embedding ?? this.embedding,
      embeddingModel: embeddingModel ?? this.embeddingModel,
      isLatest: isLatest ?? this.isLatest,
      supersedes: supersedes ?? this.supersedes,
      authorAgent: authorAgent ?? this.authorAgent,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RfcVersionEntity &&
        other.id == id &&
        other.rfcId == rfcId &&
        other.versionNo == versionNo &&
        other.summary == summary &&
        _listEquality.equals(other.embedding, embedding) &&
        other.embeddingModel == embeddingModel &&
        other.isLatest == isLatest &&
        other.supersedes == supersedes &&
        other.authorAgent == authorAgent;
  }

  @override
  int get hashCode => Object.hash(
        id,
        rfcId,
        versionNo,
        summary,
        embeddingModel,
        isLatest,
        supersedes,
        authorAgent,
      );
}
