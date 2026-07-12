import 'package:collection/collection.dart';
import 'package:oracle_core/oracle_core.dart';

import '../enums/memory_kind.dart';
import '../enums/memory_tier.dart';

const _listEquality = ListEquality<Object?>();

/// A consolidated memory — a durable, citable fact/decision/gotcha/rule written
/// by the agent (`oracle_memory_save`). Scoped to a organization OR a project.
///
/// [embedding] is the vector representation used for semantic recall (pgvector).
class MemoryEntity {
  final IdVO id;
  final IdVO? organizationId;
  final IdVO? projectId;
  final IdVO? moduleId;

  /// Optional stable identity. When set, re-saving a memory with the same
  /// [key] in the same owner supersedes the previous version (like rules),
  /// so an agent updates one memory instead of piling up near-duplicates.
  /// Keyless memories keep the old free-form, append-only behavior.
  final String? key;
  final MemoryTier tier;
  final MemoryKind kind;
  final TextVO title;
  final TextVO body;
  final List<String> tags;
  final double importance;
  final List<double>? embedding;
  final String? embeddingModel;
  final bool isLatest;
  final IdVO? supersedes;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const MemoryEntity({
    required this.id,
    this.organizationId,
    this.projectId,
    this.moduleId,
    this.key,
    required this.tier,
    required this.kind,
    required this.title,
    required this.body,
    this.tags = const [],
    this.importance = 0,
    this.embedding,
    this.embeddingModel,
    this.isLatest = true,
    this.supersedes,
    this.createdAt,
    this.updatedAt,
  });

  factory MemoryEntity.empty() => const MemoryEntity(
        id: IdVO.empty(),
        tier: MemoryTier.semantic,
        kind: MemoryKind.fact,
        title: TextVO.empty(),
        body: TextVO.empty(),
      );

  MemoryEntity copyWith({
    IdVO? id,
    IdVO? organizationId,
    IdVO? projectId,
    IdVO? moduleId,
    String? key,
    MemoryTier? tier,
    MemoryKind? kind,
    TextVO? title,
    TextVO? body,
    List<String>? tags,
    double? importance,
    List<double>? embedding,
    String? embeddingModel,
    bool? isLatest,
    IdVO? supersedes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return MemoryEntity(
      id: id ?? this.id,
      organizationId: organizationId ?? this.organizationId,
      projectId: projectId ?? this.projectId,
      moduleId: moduleId ?? this.moduleId,
      key: key ?? this.key,
      tier: tier ?? this.tier,
      kind: kind ?? this.kind,
      title: title ?? this.title,
      body: body ?? this.body,
      tags: tags ?? this.tags,
      importance: importance ?? this.importance,
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
    return other is MemoryEntity &&
        other.id == id &&
        other.organizationId == organizationId &&
        other.projectId == projectId &&
        other.moduleId == moduleId &&
        other.key == key &&
        other.tier == tier &&
        other.kind == kind &&
        other.title == title &&
        other.body == body &&
        _listEquality.equals(other.tags, tags) &&
        other.importance == importance &&
        _listEquality.equals(other.embedding, embedding) &&
        other.embeddingModel == embeddingModel &&
        other.isLatest == isLatest &&
        other.supersedes == supersedes;
  }

  @override
  int get hashCode => Object.hash(
        id,
        organizationId,
        projectId,
        moduleId,
        key,
        tier,
        kind,
        title,
        body,
        _listEquality.hash(tags),
        importance,
        embeddingModel,
        isLatest,
        supersedes,
      );
}
