import 'package:oracle_core/oracle_core.dart';

/// A project — the central scope unit. Belongs to a [organizationId] (optional, for
/// the ecosystem hierarchy) and owns architecture, rules, sessions and memory.
class ProjectEntity {
  final IdVO id;
  final IdVO? organizationId;
  final TextVO name;
  final TextVO? description;
  final String? repoPath;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const ProjectEntity({
    required this.id,
    this.organizationId,
    required this.name,
    this.description,
    this.repoPath,
    this.createdAt,
    this.updatedAt,
  });

  factory ProjectEntity.empty() =>
      const ProjectEntity(id: IdVO.empty(), name: TextVO.empty());

  ProjectEntity copyWith({
    IdVO? id,
    IdVO? organizationId,
    TextVO? name,
    TextVO? description,
    String? repoPath,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ProjectEntity(
      id: id ?? this.id,
      organizationId: organizationId ?? this.organizationId,
      name: name ?? this.name,
      description: description ?? this.description,
      repoPath: repoPath ?? this.repoPath,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ProjectEntity &&
        other.id == id &&
        other.organizationId == organizationId &&
        other.name == name &&
        other.description == description &&
        other.repoPath == repoPath &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt;
  }

  @override
  int get hashCode =>
      Object.hash(id, organizationId, name, description, repoPath, createdAt, updatedAt);
}
