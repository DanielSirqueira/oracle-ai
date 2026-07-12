import 'package:oracle_core/oracle_core.dart';

/// A module — a subdivision of a project (a service, layer, or package),
/// resolved from the agent's working subpath under the repo root. Rules,
/// memories, architecture and skills can scope to a module for knowledge that
/// is narrower than the whole project, without forking a fake project.
class ModuleEntity {
  final IdVO id;
  final IdVO projectId;

  /// Stable slug (derived from [path]) used for scoping/supersession.
  final String key;
  final TextVO name;

  /// Subpath under the repo root (e.g. `services/auth`) — the cwd auto-resolve key.
  final String? path;
  final TextVO? description;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const ModuleEntity({
    required this.id,
    required this.projectId,
    required this.key,
    required this.name,
    this.path,
    this.description,
    this.createdAt,
    this.updatedAt,
  });

  factory ModuleEntity.empty() => const ModuleEntity(
        id: IdVO.empty(), projectId: IdVO.empty(), key: '', name: TextVO.empty());

  ModuleEntity copyWith({
    IdVO? id,
    IdVO? projectId,
    String? key,
    TextVO? name,
    String? path,
    TextVO? description,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ModuleEntity(
      id: id ?? this.id,
      projectId: projectId ?? this.projectId,
      key: key ?? this.key,
      name: name ?? this.name,
      path: path ?? this.path,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ModuleEntity &&
        other.id == id &&
        other.projectId == projectId &&
        other.key == key &&
        other.name == name &&
        other.path == path &&
        other.description == description;
  }

  @override
  int get hashCode => Object.hash(id, projectId, key, name, path, description);
}
