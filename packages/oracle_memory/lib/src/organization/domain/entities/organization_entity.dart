import 'package:oracle_core/oracle_core.dart';

/// A organization — the ecosystem scope above projects. Its rules and memories are
/// inherited by every [ProjectEntity] that belongs to it.
class OrganizationEntity {
  final IdVO id;
  final TextVO name;
  final TextVO? description;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const OrganizationEntity({
    required this.id,
    required this.name,
    this.description,
    this.createdAt,
    this.updatedAt,
  });

  factory OrganizationEntity.empty() => const OrganizationEntity(id: IdVO.empty(), name: TextVO.empty());

  OrganizationEntity copyWith({
    IdVO? id,
    TextVO? name,
    TextVO? description,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return OrganizationEntity(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is OrganizationEntity &&
        other.id == id &&
        other.name == name &&
        other.description == description &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt;
  }

  @override
  int get hashCode => Object.hash(id, name, description, createdAt, updatedAt);
}
