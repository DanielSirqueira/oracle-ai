import 'package:oracle_core/oracle_core.dart';

/// Query filter for listing a project's modules (paging).
class ModuleFilter {
  final IdVO projectId;
  final String search;
  final int page;
  final int limit;

  const ModuleFilter({
    required this.projectId,
    this.search = '',
    this.page = 1,
    this.limit = 100,
  });

  int get offset => (page - 1) * limit;
}
