import 'package:oracle_core/oracle_core.dart';

import '../../domain/dtos/filters/architecture_search_filter.dart';
import '../../domain/dtos/architecture_search_result.dart';
import '../../domain/entities/architecture_entity.dart';

abstract interface class ArchitectureDatasource {
  Future<ArchitectureEntity> saveArchitecture(ArchitectureEntity architecture);

  Future<ArchitectureEntity> getByArea(IdVO projectId, String area);

  Future<List<ArchitectureSearchResult>> searchArchitecture(ArchitectureSearchFilter filter);

  /// Soft-retires an architecture page (dropped from recall, kept for audit) or,
  /// when [hard], permanently deletes it. Returns the affected page.
  Future<ArchitectureEntity> retireArchitecture(IdVO id, {String? reason, bool hard});
}
