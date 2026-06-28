import 'package:oracle_core/oracle_core.dart';

/// A product — the ecosystem scope above projects. Its rules and memories are
/// inherited by every [ProjectEntity] that belongs to it.
class ProductEntity {
  final IdVO id;
  final TextVO name;
  final TextVO? description;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const ProductEntity({
    required this.id,
    required this.name,
    this.description,
    this.createdAt,
    this.updatedAt,
  });

  factory ProductEntity.empty() => const ProductEntity(id: IdVO.empty(), name: TextVO.empty());

  ProductEntity copyWith({
    IdVO? id,
    TextVO? name,
    TextVO? description,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ProductEntity(
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
    return other is ProductEntity &&
        other.id == id &&
        other.name == name &&
        other.description == description &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt;
  }

  @override
  int get hashCode => Object.hash(id, name, description, createdAt, updatedAt);
}
