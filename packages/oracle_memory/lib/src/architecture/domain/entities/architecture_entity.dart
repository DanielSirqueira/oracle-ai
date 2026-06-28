import 'package:oracle_core/oracle_core.dart';

/// A project architecture page for an [area] (module/layer). Versioned: saving
/// the same area supersedes the previous version.
class ArchitectureEntity {
  final IdVO id;
  final IdVO projectId;
  final String area;
  final TextVO content;
  final List<double>? embedding;
  final String? embeddingModel;
  final bool isLatest;
  final IdVO? supersedes;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const ArchitectureEntity({
    required this.id,
    required this.projectId,
    required this.area,
    required this.content,
    this.embedding,
    this.embeddingModel,
    this.isLatest = true,
    this.supersedes,
    this.createdAt,
    this.updatedAt,
  });

  factory ArchitectureEntity.empty() => const ArchitectureEntity(
        id: IdVO.empty(),
        projectId: IdVO.empty(),
        area: '',
        content: TextVO.empty(),
      );

  ArchitectureEntity copyWith({
    IdVO? id,
    IdVO? projectId,
    String? area,
    TextVO? content,
    List<double>? embedding,
    String? embeddingModel,
    bool? isLatest,
    IdVO? supersedes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ArchitectureEntity(
      id: id ?? this.id,
      projectId: projectId ?? this.projectId,
      area: area ?? this.area,
      content: content ?? this.content,
      embedding: embedding ?? this.embedding,
      embeddingModel: embeddingModel ?? this.embeddingModel,
      isLatest: isLatest ?? this.isLatest,
      supersedes: supersedes ?? this.supersedes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ArchitectureEntity &&
        other.id == id &&
        other.projectId == projectId &&
        other.area == area &&
        other.content == content &&
        other.embeddingModel == embeddingModel &&
        other.isLatest == isLatest &&
        other.supersedes == supersedes;
  }

  @override
  int get hashCode =>
      Object.hash(id, projectId, area, content, embeddingModel, isLatest, supersedes);
}
