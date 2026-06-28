import 'package:oracle_core/oracle_core.dart';

import '../../domain/dtos/filters/product_filter.dart';
import '../../domain/entities/product_entity.dart';

abstract interface class ProductDatasource {
  Future<ProductEntity> registerProduct(ProductEntity product);

  Future<ProductEntity> getProductById(IdVO id);

  Future<List<ProductEntity>> listProducts(ProductFilter filter);
}
