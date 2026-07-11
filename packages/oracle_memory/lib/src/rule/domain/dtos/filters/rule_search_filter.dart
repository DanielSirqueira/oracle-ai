import 'package:oracle_core/oracle_core.dart';

import '../../enums/rule_severity.dart';

/// Retrieval mode for [RuleSearchFilter] (same semantics as memory search).
enum RuleSearchMode { keyword, semantic, hybrid }

/// Filter for hybrid rule search.
class RuleSearchFilter {
  final String query;
  final List<double>? queryEmbedding;

  /// Model that produced [queryEmbedding]; when set, the semantic leg only
  /// compares against same-model stored vectors (see MemorySearchFilter).
  final String? queryModel;

  final IdVO? projectId;
  final IdVO? organizationId;

  /// Optional scope filter.
  final String? scope;
  final List<RuleSeverity> severities;
  final RuleSearchMode mode;
  final int limit;

  const RuleSearchFilter({
    this.query = '',
    this.queryEmbedding,
    this.queryModel,
    this.projectId,
    this.organizationId,
    this.scope,
    this.severities = const [],
    this.mode = RuleSearchMode.hybrid,
    this.limit = 10,
  });

  RuleSearchFilter copyWith({List<double>? queryEmbedding, String? queryModel}) {
    return RuleSearchFilter(
      query: query,
      queryEmbedding: queryEmbedding ?? this.queryEmbedding,
      queryModel: queryModel ?? this.queryModel,
      projectId: projectId,
      organizationId: organizationId,
      scope: scope,
      severities: severities,
      mode: mode,
      limit: limit,
    );
  }
}
