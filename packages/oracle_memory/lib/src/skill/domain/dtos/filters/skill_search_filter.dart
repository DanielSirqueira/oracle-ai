import 'package:oracle_core/oracle_core.dart';

/// Retrieval mode for [SkillSearchFilter] (same semantics as memory search).
enum SkillSearchMode { keyword, semantic, hybrid }

/// Filter for hybrid skill search.
///
/// Scope semantics: results include GLOBAL skills (no owner) plus, when given,
/// the project's and/or product's skills — an agent should always see the
/// shared library, narrowed by its context.
class SkillSearchFilter {
  final String query;
  final List<double>? queryEmbedding;

  /// Model that produced [queryEmbedding]; when set, the semantic leg only
  /// compares against same-model stored vectors.
  final String? queryModel;

  final IdVO? projectId;
  final IdVO? productId;
  final SkillSearchMode mode;
  final int limit;

  const SkillSearchFilter({
    this.query = '',
    this.queryEmbedding,
    this.queryModel,
    this.projectId,
    this.productId,
    this.mode = SkillSearchMode.hybrid,
    this.limit = 10,
  });

  SkillSearchFilter copyWith({List<double>? queryEmbedding, String? queryModel}) {
    return SkillSearchFilter(
      query: query,
      queryEmbedding: queryEmbedding ?? this.queryEmbedding,
      queryModel: queryModel ?? this.queryModel,
      projectId: projectId,
      productId: productId,
      mode: mode,
      limit: limit,
    );
  }
}
