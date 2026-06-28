import 'package:oracle_core/oracle_core.dart';

import '../entities/product_entity.dart';
import '../errors/product_failure.dart';
import '../repositories/product_repository.dart';

abstract interface class RegisterProductUsecase {
  AsyncResultDart<ProductEntity, ProductFailure> call(ProductEntity product);
}

class RegisterProductUsecaseImpl implements RegisterProductUsecase {
  final ProductRepository _repository;
  const RegisterProductUsecaseImpl(this._repository);

  @override
  AsyncResultDart<ProductEntity, ProductFailure> call(ProductEntity product) async {
    if (product.name.isBlank) {
      return Failure(ValidatedFieldProductFailure(
        errorMessage: 'Product name is required',
        stackTrace: StackTrace.current,
        fields: const [FieldSystemFailure(field: 'name', message: 'Required')],
      ));
    }
    return _repository.registerProduct(product);
  }
}
