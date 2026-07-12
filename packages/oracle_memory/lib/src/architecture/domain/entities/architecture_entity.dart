import 'package:oracle_core/oracle_core.dart';

/// An architecture page for an [area] (module/layer). Versioned: saving the same
/// area in the same owner supersedes the previous version. Scoped to an
/// organization OR a project OR a module (most specific wins on recall).
class ArchitectureEntity {
  final IdVO id;
  final IdVO? organizationId;
  final IdVO? projectId;
  final IdVO? moduleId;
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
    this.organizationId,
    this.projectId,
    this.moduleId,
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
        area: '',
        content: TextVO.empty(),
      );

  ArchitectureEntity copyWith({
    IdVO? id,
    IdVO? organizationId,
    IdVO? projectId,
    IdVO? moduleId,
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
      organizationId: organizationId ?? this.organizationId,
      projectId: projectId ?? this.projectId,
      moduleId: moduleId ?? this.moduleId,
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
        other.organizationId == organizationId &&
        other.projectId == projectId &&
        other.moduleId == moduleId &&
        other.area == area &&
        other.content == content &&
        other.embeddingModel == embeddingModel &&
        other.isLatest == isLatest &&
        other.supersedes == supersedes;
  }

  @override
  int get hashCode => Object.hash(
      id, organizationId, projectId, moduleId, area, content, embeddingModel, isLatest, supersedes);
}
