import 'package:oracle_core/oracle_core.dart';

class CaptureFailure extends SystemFailure {
  CaptureFailure({
    super.label = 'Capture Error',
    required super.errorMessage,
    required super.stackTrace,
    super.fields,
  });
}

class CaptureNotFoundFailure extends CaptureFailure {
  CaptureNotFoundFailure({required super.stackTrace})
      : super(label: 'Capture Not Found', errorMessage: 'Session not found');
}

class DatasourceCaptureFailure extends CaptureFailure {
  DatasourceCaptureFailure({required super.errorMessage, required super.stackTrace})
      : super(label: 'Capture Datasource Error');
}
