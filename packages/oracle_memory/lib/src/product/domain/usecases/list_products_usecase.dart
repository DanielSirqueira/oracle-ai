import 'package:oracle_core/oracle_core.dart';

import '../dtos/filters/product_filter.dart';
import '../entities/product_entity.dart';
import '../errors/product_failure.dart';
import '../repositories/product_repository.dart';

abstract interface class ListProductsUsecase {
  AsyncResultDart<List<ProductEntity>, ProductFailure> call(ProductFilter filter);
}

class ListProductsUsecaseImpl implements ListProductsUsecase {
  final ProductRepository _repository;
  const ListProductsUsecaseImpl(this._repository);

  @override
  AsyncResultDart<List<ProductEntity>, ProductFailure> call(ProductFilter filter) =>
      _repository.listProducts(filter);
}
