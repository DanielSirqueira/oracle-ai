import 'package:collection/collection.dart';
import 'package:oracle_core/oracle_core.dart';

const _listEquality = ListEquality<Object?>();

/// A reusable agent skill (SKILL.md-style procedural know-how) stored centrally
/// so every agent shares one library instead of duplicating files per agent
/// folder. [key] is the stable slug used for supersession (and the folder name
/// when materialized); [description] is the recall trigger ("when to use").
///
/// Scope: belongs to a [projectId], OR a [productId], OR is GLOBAL (both null)
/// — ecosystem-wide skills are the common case.
class SkillEntity {
  final IdVO id;
  final IdVO? productId;
  final IdVO? projectId;
  final String key;
  final TextVO name;
  final TextVO description;

  /// The SKILL.md body (markdown). Loaded on demand (progressive disclosure);
  /// searches return name+description only.
  final TextVO content;
  final List<String> tags;
  final List<double>? embedding;
  final String? embeddingModel;
  final bool isLatest;
  final IdVO? supersedes;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const SkillEntity({
    required this.id,
    this.productId,
    this.projectId,
    required this.key,
    required this.name,
    required this.description,
    required this.content,
    this.tags = const [],
    this.embedding,
    this.embeddingModel,
    this.isLatest = true,
    this.supersedes,
    this.createdAt,
    this.updatedAt,
  });

  factory SkillEntity.empty() => const SkillEntity(
        id: IdVO.empty(),
        key: '',
        name: TextVO.empty(),
        description: TextVO.empty(),
        content: TextVO.empty(),
      );

  SkillEntity copyWith({
    IdVO? id,
    IdVO? productId,
    IdVO? projectId,
    String? key,
    TextVO? name,
    TextVO? description,
    TextVO? content,
    List<String>? tags,
    List<double>? embedding,
    String? embeddingModel,
    bool? isLatest,
    IdVO? supersedes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return SkillEntity(
      id: id ?? this.id,
      productId: productId ?? this.productId,
      projectId: projectId ?? this.projectId,
      key: key ?? this.key,
      name: name ?? this.name,
      description: description ?? this.description,
      content: content ?? this.content,
      tags: tags ?? this.tags,
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
    return other is SkillEntity &&
        other.id == id &&
        other.productId == productId &&
        other.projectId == projectId &&
        other.key == key &&
        other.name == name &&
        other.description == description &&
        other.content == content &&
        _listEquality.equals(other.tags, tags) &&
        other.embeddingModel == embeddingModel &&
        other.isLatest == isLatest &&
        other.supersedes == supersedes;
  }

  @override
  int get hashCode => Object.hash(
        id,
        productId,
        projectId,
        key,
        name,
        description,
        content,
        _listEquality.hash(tags),
        embeddingModel,
        isLatest,
        supersedes,
      );
}
