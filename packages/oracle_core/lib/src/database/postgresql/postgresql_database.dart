import 'dart:async';
import 'dart:convert';

import 'package:postgres/postgres.dart';

import '../../config/database_config.dart';
import '../../errors/database_failure.dart';
import '../data_row_type.dart';
import '../database.dart';
import '../result_database.dart';
import '../save_point_query.dart';
import '../sql_statement.dart';
import 'postgresql_type_mapper.dart';

/// Converts a PostgreSQL value into a String suitable for [DataRowType].
///
/// Uses `jsonEncode` for `Map`/`List` (JSONB columns) and Base64 for `bytea`
/// (delivered by the driver as raw `List<int>`).
String _pgValueToString(dynamic value) {
  if (value == null) return 'null';
  if (value is List<int>) return base64Encode(value);
  if (value is Map || value is List) return jsonEncode(value);
  return value.toString();
}

/// [Database] implementation backed by PostgreSQL using the `postgres`
/// package's connection [Pool].
///
/// Keeps a pool of up to [maxConnectionCount] reusable connections, initialized
/// lazily on the first operation. Connections are recycled after
/// [maxSessionUse] of cumulative use. Register as a DI singleton and call
/// [dispose] on shutdown.
class PostgreSQLDatabase implements Database {
  @override
  String host;

  @override
  int port;

  @override
  String user;

  @override
  String password;

  @override
  String database;

  @override
  bool useSsl;

  @override
  bool useCompression;

  /// Maximum number of connections the pool may open simultaneously.
  final int maxConnectionCount;

  /// Maximum cumulative use of a connection before the pool recycles it.
  final Duration maxSessionUse;

  PostgreSQLDatabase({
    this.host = '',
    this.port = 0,
    this.user = '',
    this.password = '',
    this.database = '',
    this.useSsl = false,
    this.useCompression = false,
    this.maxConnectionCount = 10,
    this.maxSessionUse = const Duration(minutes: 30),
  });

  /// Builds a database from a [DatabaseConfig].
  factory PostgreSQLDatabase.fromConfig(
    DatabaseConfig config, {
    int maxConnectionCount = 10,
    Duration maxSessionUse = const Duration(minutes: 30),
  }) {
    return PostgreSQLDatabase(
      host: config.host,
      port: config.port,
      user: config.user,
      password: config.password,
      database: config.database,
      useSsl: config.useSsl,
      useCompression: config.useCompression,
      maxConnectionCount: maxConnectionCount,
      maxSessionUse: maxSessionUse,
    );
  }

  Pool<void>? _pool;
  Future<Pool<void>>? _initFuture;
  bool _disposed = false;

  /// Ensures the pool is initialized. Idempotent and concurrency-safe
  /// (parallel operations during the first init await the same future).
  Future<Pool<void>> _ensurePool() async {
    if (_disposed) {
      throw DatabaseFailure(
        errorMessage: 'Database has been disposed and cannot be used.',
        stackTrace: StackTrace.current,
      );
    }
    final existing = _pool;
    if (existing != null) return existing;
    return _initFuture ??= _openPool();
  }

  Future<Pool<void>> _openPool() async {
    try {
      final pool = Pool.withEndpoints(
        [
          Endpoint(
            host: host,
            database: database,
            port: port,
            username: user,
            password: password,
          ),
        ],
        settings: PoolSettings(
          maxConnectionCount: maxConnectionCount,
          maxSessionUse: maxSessionUse,
          sslMode: useSsl ? SslMode.require : SslMode.disable,
          ignoreSuperfluousParameters: true,
        ),
      );
      _pool = pool;
      return pool;
    } on BadCertificateException catch (error) {
      _initFuture = null;
      throw DatabaseFailure(errorMessage: error.message, stackTrace: StackTrace.current);
    } on ServerException catch (error) {
      _initFuture = null;
      throw DatabaseFailure(errorMessage: error.message, stackTrace: StackTrace.current);
    } on PgException catch (error) {
      _initFuture = null;
      throw DatabaseFailure(errorMessage: error.message, stackTrace: StackTrace.current);
    } catch (error) {
      _initFuture = null;
      throw DatabaseFailure(errorMessage: error.toString(), stackTrace: StackTrace.current);
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final pool = _pool;
    _pool = null;
    _initFuture = null;
    if (pool != null) {
      await pool.close(force: true);
    }
  }

  @override
  Future<ResultDatabase> select(SqlStatement statement) async {
    statement.validate();
    try {
      final pool = await _ensurePool();
      final response = await pool.execute(
        Sql.named(statement.sql, substitution: ':'),
        parameters: unwrapParamsForPostgres(statement.params),
      );
      return _buildResultFromResponse(response, returningForInsertId: false);
    } on DatabaseFailure {
      rethrow;
    } on BadCertificateException catch (error) {
      throw DatabaseFailure(errorMessage: error.message, stackTrace: StackTrace.current);
    } on ServerException catch (error) {
      throw DatabaseFailure(errorMessage: error.message, stackTrace: StackTrace.current);
    } on PgException catch (error) {
      throw DatabaseFailure(errorMessage: error.message, stackTrace: StackTrace.current);
    } catch (error) {
      throw DatabaseFailure(errorMessage: error.toString(), stackTrace: StackTrace.current);
    }
  }

  @override
  Future<ResultDatabase> executeUpdate(SqlStatement statement) async {
    statement.validate();
    try {
      final pool = await _ensurePool();
      final response = await pool.execute(
        Sql.named(statement.sql, substitution: ':'),
        parameters: unwrapParamsForPostgres(statement.params),
      );
      return _buildResultFromResponse(
        response,
        returningForInsertId: statement.sql.toUpperCase().contains('RETURNING'),
        useFirstRowSchema: true,
      );
    } on DatabaseFailure {
      rethrow;
    } on BadCertificateException catch (error) {
      throw DatabaseFailure(errorMessage: error.message, stackTrace: StackTrace.current);
    } on ServerException catch (error) {
      throw DatabaseFailure(errorMessage: error.message, stackTrace: StackTrace.current);
    } on PgException catch (error) {
      throw DatabaseFailure(errorMessage: error.message, stackTrace: StackTrace.current);
    } catch (e) {
      throw DatabaseFailure(errorMessage: e.toString(), stackTrace: StackTrace.current);
    }
  }

  /// Converts the driver [Result] into a [ResultDatabase].
  ResultDatabase _buildResultFromResponse(
    Result response, {
    required bool returningForInsertId,
    bool useFirstRowSchema = false,
  }) {
    final rows = <Map<String, DataRowType>>[];

    for (final row in response) {
      final dataRow = <String, DataRowType>{};
      final columnCount =
          useFirstRowSchema ? response.first.length : row.schema.columns.length;
      for (var i = 0; i < columnCount; i++) {
        final columnName = row.schema.columns[i].columnName ?? i.toString();
        final value = useFirstRowSchema ? response.first[i] : row[i];
        dataRow[columnName] = DataRowType(_pgValueToString(value));
      }
      rows.add(dataRow);
    }

    return ResultDatabase(
      rows: rows,
      numberOfColumns: response.schema.columns.length,
      numberOfRows: response.length,
      affectedRows: BigInt.from(response.affectedRows),
      lastInsertId: BigInt.from(
        returningForInsertId && response.isNotEmpty
            ? _extractLastInsertId(response.last.first)
            : 0,
      ),
    );
  }

  @override
  Future<void> executeScript(String sql) async {
    try {
      final pool = await _ensurePool();
      await pool.execute(Sql(sql), ignoreRows: true);
    } on DatabaseFailure {
      rethrow;
    } on BadCertificateException catch (error) {
      throw DatabaseFailure(errorMessage: error.message, stackTrace: StackTrace.current);
    } on ServerException catch (error) {
      throw DatabaseFailure(errorMessage: error.message, stackTrace: StackTrace.current);
    } on PgException catch (error) {
      throw DatabaseFailure(errorMessage: error.message, stackTrace: StackTrace.current);
    } catch (error) {
      throw DatabaseFailure(errorMessage: error.toString(), stackTrace: StackTrace.current);
    }
  }

  int _extractLastInsertId(dynamic value) {
    if (value is BigInt) return value.toInt();
    if (value is int) return value;
    final str = value.toString();
    if (str.isEmpty) return 0;
    return int.tryParse(str) ?? 0;
  }

  @override
  Future<List<ResultDatabase>> executeSavePoint(List<SavePointQuery> queries) async {
    final pool = await _ensurePool();
    try {
      return await pool.runTx<List<ResultDatabase>>((tx) async {
        final results = <ResultDatabase>[];
        for (final query in queries) {
          query.statement.validate();
          final response = await tx.execute(
            Sql.named(query.sql, substitution: ':'),
            parameters: unwrapParamsForPostgres(query.params),
          );
          final result = _buildResultFromResponse(
            response,
            returningForInsertId: query.sql.toUpperCase().contains('RETURNING'),
          );
          query.lastInsertId = result.lastInsertId;
          results.add(result);

          final callback = query.savePointCallback;
          if (callback != null) {
            for (final child in await callback(result)) {
              await _executeSavePointCallback(tx, child, results);
            }
          }
        }
        return results;
      });
    } on DatabaseFailure {
      rethrow;
    } on BadCertificateException catch (error) {
      throw DatabaseFailure(errorMessage: error.message, stackTrace: StackTrace.current);
    } on ServerException catch (error) {
      throw DatabaseFailure(errorMessage: error.message, stackTrace: StackTrace.current);
    } on PgException catch (error) {
      throw DatabaseFailure(errorMessage: error.message, stackTrace: StackTrace.current);
    } catch (error) {
      throw DatabaseFailure(errorMessage: error.toString(), stackTrace: StackTrace.current);
    }
  }

  Future<void> _executeSavePointCallback(
    TxSession tx,
    SavePointQuery query,
    List<ResultDatabase> results,
  ) async {
    query.statement.validate();
    final response = await tx.execute(
      Sql.named(query.sql, substitution: ':'),
      parameters: unwrapParamsForPostgres(query.params),
    );
    final result = _buildResultFromResponse(
      response,
      returningForInsertId: query.sql.toUpperCase().contains('RETURNING'),
      useFirstRowSchema: true,
    );
    query.lastInsertId = result.lastInsertId;
    results.add(result);

    final nested = query.savePointCallback;
    if (nested != null) {
      for (final child in await nested(result)) {
        await _executeSavePointCallback(tx, child, results);
      }
    }
  }
}
