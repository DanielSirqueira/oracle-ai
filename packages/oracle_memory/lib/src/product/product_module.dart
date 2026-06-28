import 'package:oracle_core/oracle_core.dart';

import 'domain/repositories/product_repository.dart';
import 'domain/usecases/get_product_by_id_usecase.dart';
import 'domain/usecases/list_products_usecase.dart';
import 'domain/usecases/register_product_usecase.dart';
import 'external/datasources/database/database_product_datasource.dart';
import 'infra/datasources/product_datasource.dart';
import 'infra/repositories/product_repository_impl.dart';

class ProductModule extends Module {
  @override
  void binds(AutoInjector i) {
    i
      ..addLazySingleton<ProductDatasource>(DatabaseProductDatasource.new)
      ..addLazySingleton<ProductRepository>(ProductRepositoryImpl.new)
      ..addLazySingleton<RegisterProductUsecase>(RegisterProductUsecaseImpl.new)
      ..addLazySingleton<GetProductByIdUsecase>(GetProductByIdUsecaseImpl.new)
      ..addLazySingleton<ListProductsUsecase>(ListProductsUsecaseImpl.new);
  }
}
