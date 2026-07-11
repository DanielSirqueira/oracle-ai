import 'package:collection/collection.dart';
import 'package:oracle_core/oracle_core.dart';

import '../enums/rule_severity.dart';

const _listEquality = ListEquality<Object?>();

/// A development rule. Belongs to a [organizationId] (inherited by all its projects)
/// OR a [projectId] (project-specific override). [key] is a stable slug used for
/// supersession; [scope] narrows it to a module/folder/area (e.g. `controllers`).
class RuleEntity {
  final IdVO id;
  final IdVO? organizationId;
  final IdVO? projectId;
  final String key;
  final String scope;
  final TextVO title;
  final TextVO content;
  final RuleSeverity severity;

  /// Ranking within the same [severity] (0..100, default 50). LOWER wins —
  /// priority 1 is the most relevant, 100 the least; delivered ascending in
  /// `rulesForTask`. Orthogonal to [severity]: severity is obligation
  /// (must vs should), priority is ordering/relevance.
  final int priority;
  final List<String> tags;
  final List<double>? embedding;
  final String? embeddingModel;
  final bool isLatest;
  final IdVO? supersedes;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const RuleEntity({
    required this.id,
    this.organizationId,
    this.projectId,
    required this.key,
    required this.scope,
    required this.title,
    required this.content,
    this.severity = RuleSeverity.recommended,
    this.priority = 50,
    this.tags = const [],
    this.embedding,
    this.embeddingModel,
    this.isLatest = true,
    this.supersedes,
    this.createdAt,
    this.updatedAt,
  });

  factory RuleEntity.empty() => const RuleEntity(
        id: IdVO.empty(),
        key: '',
        scope: '',
        title: TextVO.empty(),
        content: TextVO.empty(),
      );

  RuleEntity copyWith({
    IdVO? id,
    IdVO? organizationId,
    IdVO? projectId,
    String? key,
    String? scope,
    TextVO? title,
    TextVO? content,
    RuleSeverity? severity,
    int? priority,
    List<String>? tags,
    List<double>? embedding,
    String? embeddingModel,
    bool? isLatest,
    IdVO? supersedes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return RuleEntity(
      id: id ?? this.id,
      organizationId: organizationId ?? this.organizationId,
      projectId: projectId ?? this.projectId,
      key: key ?? this.key,
      scope: scope ?? this.scope,
      title: title ?? this.title,
      content: content ?? this.content,
      severity: severity ?? this.severity,
      priority: priority ?? this.priority,
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
    return other is RuleEntity &&
        other.id == id &&
        other.organizationId == organizationId &&
        other.projectId == projectId &&
        other.key == key &&
        other.scope == scope &&
        other.title == title &&
        other.content == content &&
        other.severity == severity &&
        other.priority == priority &&
        _listEquality.equals(other.tags, tags) &&
        other.embeddingModel == embeddingModel &&
        other.isLatest == isLatest &&
        other.supersedes == supersedes;
  }

  @override
  int get hashCode => Object.hash(
        id,
        organizationId,
        projectId,
        key,
        scope,
        title,
        content,
        severity,
        priority,
        _listEquality.hash(tags),
        embeddingModel,
        isLatest,
        supersedes,
      );
}
