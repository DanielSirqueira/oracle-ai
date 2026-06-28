import 'package:oracle_core/oracle_core.dart';

import '../dtos/filters/architecture_search_filter.dart';
import '../dtos/architecture_search_result.dart';
import '../entities/architecture_entity.dart';
import '../errors/architecture_failure.dart';

abstract interface class ArchitectureRepository {
  /// Saves an architecture page, superseding the current one for the same
  /// (project, area).
  AsyncResultDart<ArchitectureEntity, ArchitectureFailure> saveArchitecture(
    ArchitectureEntity architecture,
  );

  /// Current architecture page for a project area.
  AsyncResultDart<ArchitectureEntity, ArchitectureFailure> getByArea(IdVO projectId, String area);

  AsyncResultDart<List<ArchitectureSearchResult>, ArchitectureFailure> searchArchitecture(
    ArchitectureSearchFilter filter,
  );

  /// Retires an architecture page: soft by default (dropped from recall, kept
  /// for audit), or permanently removed when [hard] is true.
  AsyncResultDart<ArchitectureEntity, ArchitectureFailure> retireArchitecture(
    IdVO id, {
    String? reason,
    bool hard,
  });
}
