import 'package:oracle_core/oracle_core.dart';

/// Base failure for the memory module.
class MemoryFailure extends SystemFailure {
  MemoryFailure({
    super.label = 'Memory Error',
    required super.errorMessage,
    required super.stackTrace,
    super.fields,
  });
}

class MemoryNotFoundFailure extends MemoryFailure {
  MemoryNotFoundFailure({required super.stackTrace})
      : super(label: 'Memory Not Found', errorMessage: 'Memory not found');
}

class DatasourceMemoryFailure extends MemoryFailure {
  DatasourceMemoryFailure({required super.errorMessage, required super.stackTrace})
      : super(label: 'Memory Datasource Error');
}

class ValidatedFieldMemoryFailure extends MemoryFailure {
  ValidatedFieldMemoryFailure({
    required super.errorMessage,
    required super.stackTrace,
    required super.fields,
  }) : super(label: 'Memory Validation Error');
}
