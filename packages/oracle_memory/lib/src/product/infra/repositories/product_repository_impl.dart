import 'package:oracle_core/oracle_core.dart';

import '../../domain/dtos/filters/product_filter.dart';
import '../../domain/entities/product_entity.dart';
import '../../domain/errors/product_failure.dart';
import '../../domain/repositories/product_repository.dart';
import '../datasources/product_datasource.dart';

class ProductRepositoryImpl implements ProductRepository {
  final ProductDatasource _datasource;
  const ProductRepositoryImpl({required ProductDatasource datasource}) : _datasource = datasource;

  @override
  AsyncResultDart<ProductEntity, ProductFailure> registerProduct(ProductEntity product) async {
    try {
      return Success(await _datasource.registerProduct(product));
    } on ProductFailure catch (failure) {
      return Failure(failure);
    }
  }

  @override
  AsyncResultDart<ProductEntity, ProductFailure> getProductById(IdVO id) async {
    try {
      return Success(await _datasource.getProductById(id));
    } on ProductFailure catch (failure) {
      return Failure(failure);
    }
  }

  @override
  AsyncResultDart<List<ProductEntity>, ProductFailure> listProducts(ProductFilter filter) async {
    try {
      return Success(await _datasource.listProducts(filter));
    } on ProductFailure catch (failure) {
      return Failure(failure);
    }
  }
}
