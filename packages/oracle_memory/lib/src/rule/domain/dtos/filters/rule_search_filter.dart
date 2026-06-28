import 'package:oracle_core/oracle_core.dart';

import '../../enums/rule_severity.dart';

/// Retrieval mode for [RuleSearchFilter] (same semantics as memory search).
enum RuleSearchMode { keyword, semantic, hybrid }

/// Filter for hybrid rule search.
class RuleSearchFilter {
  final String query;
  final List<double>? queryEmbedding;
  final IdVO? projectId;
  final IdVO? productId;

  /// Optional scope filter.
  final String? scope;
  final List<RuleSeverity> severities;
  final RuleSearchMode mode;
  final int limit;

  const RuleSearchFilter({
    this.query = '',
    this.queryEmbedding,
    this.projectId,
    this.productId,
    this.scope,
    this.severities = const [],
    this.mode = RuleSearchMode.hybrid,
    this.limit = 10,
  });

  RuleSearchFilter copyWith({List<double>? queryEmbedding}) {
    return RuleSearchFilter(
      query: query,
      queryEmbedding: queryEmbedding ?? this.queryEmbedding,
      projectId: projectId,
      productId: productId,
      scope: scope,
      severities: severities,
      mode: mode,
      limit: limit,
    );
  }
}
