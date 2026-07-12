import 'package:oracle_core/oracle_core.dart';

import '../../enums/memory_kind.dart';
import '../../enums/memory_tier.dart';

/// Retrieval mode for [MemorySearchFilter].
enum SearchMode {
  /// Full-text only (BM25-ish via tsvector).
  keyword,

  /// Vector similarity only (pgvector).
  semantic,

  /// Vector + full-text fused with Reciprocal Rank Fusion.
  hybrid,
}

/// Filter for hybrid memory search (mirrors a subset of `oracle_search`).
///
/// When [mode] is [SearchMode.hybrid], the effective mode degrades gracefully:
/// only [query] → keyword; only [queryEmbedding] → semantic; both → hybrid.
class MemorySearchFilter {
  /// Free-text query (drives the lexical leg).
  final String query;

  /// Query embedding (drives the semantic leg). Must match the index dimension.
  final List<double>? queryEmbedding;

  /// Model that produced [queryEmbedding]. When set, the semantic leg only
  /// compares against stored vectors from the SAME model — cross-model cosine
  /// distances are meaningless, so this prevents garbage recall after a provider
  /// switch (until the store is re-embedded).
  final String? queryModel;

  final IdVO? projectId;
  final IdVO? organizationId;
  final IdVO? moduleId;
  final List<MemoryTier> tiers;
  final List<MemoryKind> kinds;
  final SearchMode mode;
  final int limit;

  const MemorySearchFilter({
    this.query = '',
    this.queryEmbedding,
    this.queryModel,
    this.projectId,
    this.organizationId,
    this.moduleId,
    this.tiers = const [],
    this.kinds = const [],
    this.mode = SearchMode.hybrid,
    this.limit = 10,
  });

  MemorySearchFilter copyWith({List<double>? queryEmbedding, String? queryModel}) {
    return MemorySearchFilter(
      query: query,
      queryEmbedding: queryEmbedding ?? this.queryEmbedding,
      queryModel: queryModel ?? this.queryModel,
      projectId: projectId,
      organizationId: organizationId,
      moduleId: moduleId,
      tiers: tiers,
      kinds: kinds,
      mode: mode,
      limit: limit,
    );
  }
}
