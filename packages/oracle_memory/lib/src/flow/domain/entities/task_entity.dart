import 'package:collection/collection.dart';
import 'package:oracle_core/oracle_core.dart';

import '../enums/task_status.dart';

const _listEquality = ListEquality<Object?>();

/// A development demand in the backlog. Anchors on exactly one scope level
/// (organization / project / module), like rfcs/rules/memories, and may point at
/// the RFC that specifies it. Creating a task and choosing a flow triggers the
/// full development cycle. [source] records who filed it (human / agent / flow);
/// the title+description are embedded for semantic dedup ("asked before?").
class TaskEntity {
  final IdVO id;
  final IdVO? organizationId;
  final IdVO? projectId;
  final IdVO? moduleId;
  final TextVO title;
  final String description;
  final TaskStatus status;
  final int priority;
  final String source;
  final IdVO? rfcId;
  final String createdBy;
  final List<double>? embedding;
  final String? embeddingModel;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const TaskEntity({
    required this.id,
    this.organizationId,
    this.projectId,
    this.moduleId,
    required this.title,
    this.description = '',
    this.status = TaskStatus.backlog,
    this.priority = 50,
    this.source = 'human',
    this.rfcId,
    this.createdBy = 'human',
    this.embedding,
    this.embeddingModel,
    this.createdAt,
    this.updatedAt,
  });

  factory TaskEntity.empty() =>
      const TaskEntity(id: IdVO.empty(), title: TextVO.empty());

  TaskEntity copyWith({
    IdVO? id,
    IdVO? organizationId,
    IdVO? projectId,
    IdVO? moduleId,
    TextVO? title,
    String? description,
    TaskStatus? status,
    int? priority,
    String? source,
    IdVO? rfcId,
    String? createdBy,
    List<double>? embedding,
    String? embeddingModel,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return TaskEntity(
      id: id ?? this.id,
      organizationId: organizationId ?? this.organizationId,
      projectId: projectId ?? this.projectId,
      moduleId: moduleId ?? this.moduleId,
      title: title ?? this.title,
      description: description ?? this.description,
      status: status ?? this.status,
      priority: priority ?? this.priority,
      source: source ?? this.source,
      rfcId: rfcId ?? this.rfcId,
      createdBy: createdBy ?? this.createdBy,
      embedding: embedding ?? this.embedding,
      embeddingModel: embeddingModel ?? this.embeddingModel,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TaskEntity &&
        other.id == id &&
        other.organizationId == organizationId &&
        other.projectId == projectId &&
        other.moduleId == moduleId &&
        other.title == title &&
        other.description == description &&
        other.status == status &&
        other.priority == priority &&
        other.source == source &&
        other.rfcId == rfcId &&
        other.createdBy == createdBy &&
        _listEquality.equals(other.embedding, embedding) &&
        other.embeddingModel == embeddingModel;
  }

  @override
  int get hashCode => Object.hash(
    id,
    organizationId,
    projectId,
    moduleId,
    title,
    description,
    status,
    priority,
    source,
    rfcId,
    createdBy,
    embeddingModel,
  );
}
