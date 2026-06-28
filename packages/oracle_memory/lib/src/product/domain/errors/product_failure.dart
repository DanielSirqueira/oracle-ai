import 'package:oracle_core/oracle_core.dart';

class ProductFailure extends SystemFailure {
  ProductFailure({
    super.label = 'Product Error',
    required super.errorMessage,
    required super.stackTrace,
    super.fields,
  });
}

class ProductNotFoundFailure extends ProductFailure {
  ProductNotFoundFailure({required super.stackTrace})
      : super(label: 'Product Not Found', errorMessage: 'Product not found');
}

class DatasourceProductFailure extends ProductFailure {
  DatasourceProductFailure({required super.errorMessage, required super.stackTrace})
      : super(label: 'Product Datasource Error');
}

class ValidatedFieldProductFailure extends ProductFailure {
  ValidatedFieldProductFailure({
    required super.errorMessage,
    required super.stackTrace,
    required super.fields,
  }) : super(label: 'Product Validation Error');
}
