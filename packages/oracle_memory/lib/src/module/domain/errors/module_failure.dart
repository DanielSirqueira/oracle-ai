import 'package:oracle_core/oracle_core.dart';

/// Base failure for the module feature.
class ModuleFailure extends SystemFailure {
  ModuleFailure({
    super.label = 'Module Error',
    required super.errorMessage,
    required super.stackTrace,
    super.fields,
  });
}

/// The requested module does not exist.
class ModuleNotFoundFailure extends ModuleFailure {
  ModuleNotFoundFailure({required super.stackTrace})
      : super(label: 'Module Not Found', errorMessage: 'Module not found');
}

/// A database/datasource error while accessing modules.
class DatasourceModuleFailure extends ModuleFailure {
  DatasourceModuleFailure({required super.errorMessage, required super.stackTrace})
      : super(label: 'Module Datasource Error');
}

/// Domain validation error (e.g. a required field is missing).
class ValidatedFieldModuleFailure extends ModuleFailure {
  ValidatedFieldModuleFailure({
    required super.errorMessage,
    required super.stackTrace,
    required super.fields,
  }) : super(label: 'Module Validation Error');
}
