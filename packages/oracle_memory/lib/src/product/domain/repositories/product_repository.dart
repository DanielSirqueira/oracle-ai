import 'package:oracle_core/oracle_core.dart';

import '../dtos/filters/product_filter.dart';
import '../entities/product_entity.dart';
import '../errors/product_failure.dart';

abstract interface class ProductRepository {
  AsyncResultDart<ProductEntity, ProductFailure> registerProduct(ProductEntity product);

  AsyncResultDart<ProductEntity, ProductFailure> getProductById(IdVO id);

  AsyncResultDart<List<ProductEntity>, ProductFailure> listProducts(ProductFilter filter);
}
