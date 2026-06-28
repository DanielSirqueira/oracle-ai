import 'package:oracle_core/oracle_core.dart';

enum ArchitectureSearchMode { keyword, semantic, hybrid }

/// Filter for hybrid architecture search.
class ArchitectureSearchFilter {
  final String query;
  final List<double>? queryEmbedding;
  final IdVO? projectId;
  final String? area;
  final ArchitectureSearchMode mode;
  final int limit;

  const ArchitectureSearchFilter({
    this.query = '',
    this.queryEmbedding,
    this.projectId,
    this.area,
    this.mode = ArchitectureSearchMode.hybrid,
    this.limit = 10,
  });

  ArchitectureSearchFilter copyWith({List<double>? queryEmbedding}) {
    return ArchitectureSearchFilter(
      query: query,
      queryEmbedding: queryEmbedding ?? this.queryEmbedding,
      projectId: projectId,
      area: area,
      mode: mode,
      limit: limit,
    );
  }
}
