import 'package:collection/collection.dart';
import 'package:oracle_core/oracle_core.dart';

const _listEquality = ListEquality<Object?>();

/// One section of an RFC version. The body is SECTIONED: each canonical
/// checklist section is a commentable, vectorizable row, and the pair
/// ([required], [coverage]) is what gates completion when something is thin.
class RfcSectionEntity {
  final IdVO id;
  final IdVO versionId;

  /// Canonical checklist key (context|problem|goals|scope|...).
  final String sectionKey;
  final TextVO content;
  final bool required;

  /// Coverage of a required section: missing|thin|covered.
  final String coverage;
  final List<double>? embedding;
  final String? embeddingModel;
  final DateTime? createdAt;

  const RfcSectionEntity({
    required this.id,
    required this.versionId,
    required this.sectionKey,
    required this.content,
    this.required = false,
    this.coverage = 'missing',
    this.embedding,
    this.embeddingModel,
    this.createdAt,
  });

  RfcSectionEntity copyWith({
    IdVO? id,
    IdVO? versionId,
    String? sectionKey,
    TextVO? content,
    bool? required,
    String? coverage,
    List<double>? embedding,
    String? embeddingModel,
    DateTime? createdAt,
  }) {
    return RfcSectionEntity(
      id: id ?? this.id,
      versionId: versionId ?? this.versionId,
      sectionKey: sectionKey ?? this.sectionKey,
      content: content ?? this.content,
      required: required ?? this.required,
      coverage: coverage ?? this.coverage,
      embedding: embedding ?? this.embedding,
      embeddingModel: embeddingModel ?? this.embeddingModel,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RfcSectionEntity &&
        other.id == id &&
        other.versionId == versionId &&
        other.sectionKey == sectionKey &&
        other.content == content &&
        other.required == required &&
        other.coverage == coverage &&
        _listEquality.equals(other.embedding, embedding) &&
        other.embeddingModel == embeddingModel;
  }

  @override
  int get hashCode => Object.hash(
        id,
        versionId,
        sectionKey,
        content,
        required,
        coverage,
        embeddingModel,
      );
}
