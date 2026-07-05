import '../entities/memory_entity.dart';

/// A latest memory found near a query embedding, with its cosine [distance]
/// (lower = more similar). Powers the save-time "you already have something
/// like this" signal that nudges agents to consolidate instead of duplicating.
class MemoryNeighbor {
  final MemoryEntity memory;
  final double distance;

  const MemoryNeighbor({required this.memory, required this.distance});
}
