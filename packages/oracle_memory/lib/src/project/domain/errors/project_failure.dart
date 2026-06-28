import 'package:oracle_core/oracle_core.dart';

/// Base failure for the project module.
class ProjectFailure extends SystemFailure {
  ProjectFailure({
    super.label = 'Project Error',
    required super.errorMessage,
    required super.stackTrace,
    super.fields,
  });
}

/// The requested project does not exist.
class ProjectNotFoundFailure extends ProjectFailure {
  ProjectNotFoundFailure({required super.stackTrace})
      : super(label: 'Project Not Found', errorMessage: 'Project not found');
}

/// A database/datasource error while accessing projects.
class DatasourceProjectFailure extends ProjectFailure {
  DatasourceProjectFailure({required super.errorMessage, required super.stackTrace})
      : super(label: 'Project Datasource Error');
}

/// Domain validation error (e.g. a required field is missing).
class ValidatedFieldProjectFailure extends ProjectFailure {
  ValidatedFieldProjectFailure({
    required super.errorMessage,
    required super.stackTrace,
    required super.fields,
  }) : super(label: 'Project Validation Error');
}
