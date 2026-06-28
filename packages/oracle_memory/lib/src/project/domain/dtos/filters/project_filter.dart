import 'package:oracle_core/oracle_core.dart';

/// Query filter for listing projects (search + optional product scope + paging).
class ProjectFilter {
  final String search;
  final IdVO? productId;
  final int page;
  final int limit;

  const ProjectFilter({
    this.search = '',
    this.productId,
    this.page = 1,
    this.limit = 50,
  });

  /// Zero-based offset derived from [page]/[limit].
  int get offset => (page - 1) * limit;

  ProjectFilter copyWith({String? search, IdVO? productId, int? page, int? limit}) {
    return ProjectFilter(
      search: search ?? this.search,
      productId: productId ?? this.productId,
      page: page ?? this.page,
      limit: limit ?? this.limit,
    );
  }
}
