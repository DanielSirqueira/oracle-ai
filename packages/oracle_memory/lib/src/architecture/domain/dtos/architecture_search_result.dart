import '../entities/architecture_entity.dart';

class ArchitectureSearchResult {
  final ArchitectureEntity architecture;
  final double score;

  const ArchitectureSearchResult({required this.architecture, required this.score});
}
