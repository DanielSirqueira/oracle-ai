import 'package:oracle_core/oracle_core.dart';

import '../../../domain/dtos/filters/product_filter.dart';
import '../../../domain/entities/product_entity.dart';
import '../../../domain/errors/product_failure.dart';
import '../../../infra/datasources/product_datasource.dart';
import '../../mappers/database/database_product_mapper.dart';

class DatabaseProductDatasource implements ProductDatasource {
  final Database _database;
  const DatabaseProductDatasource({required Database database}) : _database = database;

  static const _columns = 'id, name, description, created_at, updated_at';

  @override
  Future<ProductEntity> registerProduct(ProductEntity product) async {
    try {
      final result = await _database.executeUpdate(SqlStatement(
        'INSERT INTO products (name, description) VALUES (:name, :description) '
        'RETURNING id, created_at, updated_at',
        DatabaseProductMapper.toInsertParams(product),
      ));
      final row = result.rows.first;
      return product.copyWith(
        id: IdVO(row['id']!.toText()!),
        createdAt: row['created_at']?.toDateTime(),
        updatedAt: row['updated_at']?.toDateTime(),
      );
    } on DatabaseFailure catch (error) {
      throw DatasourceProductFailure(errorMessage: error.errorMessage, stackTrace: StackTrace.current);
    }
  }

  @override
  Future<ProductEntity> getProductById(IdVO id) async {
    try {
      final result = await _database.select(SqlStatement(
        'SELECT $_columns FROM products WHERE id = :id::uuid',
        {'id': id.value},
      ));
      if (result.rows.isEmpty) {
        throw ProductNotFoundFailure(stackTrace: StackTrace.current);
      }
      return DatabaseProductMapper.fromRow(result.rows.first);
    } on DatabaseFailure catch (error) {
      throw DatasourceProductFailure(errorMessage: error.errorMessage, stackTrace: StackTrace.current);
    }
  }

  @override
  Future<List<ProductEntity>> listProducts(ProductFilter filter) async {
    try {
      final params = <String, Object?>{'limit': filter.limit, 'offset': filter.offset};
      var where = '';
      if (filter.search.trim().isNotEmpty) {
        where = 'WHERE name ILIKE :like';
        params['like'] = '%${filter.search.trim()}%';
      }
      final result = await _database.select(SqlStatement(
        'SELECT $_columns FROM products $where ORDER BY name LIMIT :limit OFFSET :offset',
        params,
      ));
      return result.rows.map(DatabaseProductMapper.fromRow).toList();
    } on DatabaseFailure catch (error) {
      throw DatasourceProductFailure(errorMessage: error.errorMessage, stackTrace: StackTrace.current);
    }
  }
}
