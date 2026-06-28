import 'package:oracle_core/oracle_core.dart';

import '../entities/product_entity.dart';
import '../errors/product_failure.dart';
import '../repositories/product_repository.dart';

abstract interface class GetProductByIdUsecase {
  AsyncResultDart<ProductEntity, ProductFailure> call(IdVO id);
}

class GetProductByIdUsecaseImpl implements GetProductByIdUsecase {
  final ProductRepository _repository;
  const GetProductByIdUsecaseImpl(this._repository);

  @override
  AsyncResultDart<ProductEntity, ProductFailure> call(IdVO id) => _repository.getProductById(id);
}
