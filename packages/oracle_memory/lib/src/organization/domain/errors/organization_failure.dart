import 'package:oracle_core/oracle_core.dart';

class OrganizationFailure extends SystemFailure {
  OrganizationFailure({
    super.label = 'Organization Error',
    required super.errorMessage,
    required super.stackTrace,
    super.fields,
  });
}

class OrganizationNotFoundFailure extends OrganizationFailure {
  OrganizationNotFoundFailure({required super.stackTrace})
      : super(label: 'Organization Not Found', errorMessage: 'Organization not found');
}

class DatasourceOrganizationFailure extends OrganizationFailure {
  DatasourceOrganizationFailure({required super.errorMessage, required super.stackTrace})
      : super(label: 'Organization Datasource Error');
}

class ValidatedFieldOrganizationFailure extends OrganizationFailure {
  ValidatedFieldOrganizationFailure({
    required super.errorMessage,
    required super.stackTrace,
    required super.fields,
  }) : super(label: 'Organization Validation Error');
}
