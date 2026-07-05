import 'package:oracle_core/oracle_core.dart';

enum ArchitectureSearchMode { keyword, semantic, hybrid }

/// Filter for hybrid architecture search.
class ArchitectureSearchFilter {
  final String query;
  final List<double>? queryEmbedding;

  /// Model that produced [queryEmbedding]; when set, the semantic leg only
  /// compares against same-model stored vectors (see MemorySearchFilter).
  final String? queryModel;

  final IdVO? projectId;
  final String? area;
  final ArchitectureSearchMode mode;
  final int limit;

  const ArchitectureSearchFilter({
    this.query = '',
    this.queryEmbedding,
    this.queryModel,
    this.projectId,
    this.area,
    this.mode = ArchitectureSearchMode.hybrid,
    this.limit = 10,
  });

  ArchitectureSearchFilter copyWith({List<double>? queryEmbedding, String? queryModel}) {
    return ArchitectureSearchFilter(
      query: query,
      queryEmbedding: queryEmbedding ?? this.queryEmbedding,
      queryModel: queryModel ?? this.queryModel,
      projectId: projectId,
      area: area,
      mode: mode,
      limit: limit,
    );
  }
}
