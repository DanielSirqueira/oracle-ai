import 'package:oracle_core/oracle_core.dart';

/// Query filter for listing projects (search + optional organization scope + paging).
class ProjectFilter {
  final String search;
  final IdVO? organizationId;
  final int page;
  final int limit;

  const ProjectFilter({
    this.search = '',
    this.organizationId,
    this.page = 1,
    this.limit = 50,
  });

  /// Zero-based offset derived from [page]/[limit].
  int get offset => (page - 1) * limit;

  ProjectFilter copyWith({String? search, IdVO? organizationId, int? page, int? limit}) {
    return ProjectFilter(
      search: search ?? this.search,
      organizationId: organizationId ?? this.organizationId,
      page: page ?? this.page,
      limit: limit ?? this.limit,
    );
  }
}
