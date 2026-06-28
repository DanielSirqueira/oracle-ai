import 'result_database.dart';
import 'save_point_query.dart';
import 'sql_statement.dart';

/// Contract for database operations.
///
/// **Connection model — internal pool:** implementations keep an internal pool
/// of reusable connections. Each [select]/[executeUpdate]/[executeScript]/
/// [executeSavePoint] checks out a free connection, runs, and returns it.
/// Concurrent calls run in parallel on different connections. The pool is
/// initialized lazily on the first operation. There is no per-operation
/// `connect()`/`disconnect()`.
///
/// **Lifecycle:** the pool lives as long as the instance. Registered as a
/// singleton in DI, it lives for the app's lifetime. Call [dispose] once on
/// shutdown to close every open connection.
///
/// **Security:** all SQL goes through [SqlStatement], which is parameterized —
/// the interface never accepts freely concatenated SQL, eliminating SQL
/// injection by contract.
abstract interface class Database {
  /// Database host.
  String get host;

  /// Connection port.
  int get port;

  /// Database user.
  String get user;

  /// Database password.
  String get password;

  /// Database name.
  String get database;

  /// Whether the connection uses SSL.
  bool get useSsl;

  /// Whether the connection uses compression.
  bool get useCompression;

  /// Closes every pooled connection. Call once on shutdown. Idempotent —
  /// calls after the first are no-ops. Operations after [dispose] throw.
  Future<void> dispose();

  /// Runs a parameterized `SELECT`.
  Future<ResultDatabase> select(SqlStatement statement);

  /// Runs a parameterized `INSERT`/`UPDATE`/`DELETE`.
  Future<ResultDatabase> executeUpdate(SqlStatement statement);

  /// Runs a raw, multi-statement SQL script (no parameters).
  ///
  /// Used by migrations to run `.sql` files with several `;`-separated
  /// commands. The SQL MUST be static (developer-controlled migration files).
  Future<void> executeScript(String sql);

  /// Runs a sequence of queries in a single transaction with save points.
  ///
  /// The whole transaction (including nested callbacks) uses one pooled
  /// connection with `BEGIN`/`COMMIT`/`ROLLBACK`. If any query fails, the
  /// driver rolls back and the error is rethrown as a database failure.
  Future<List<ResultDatabase>> executeSavePoint(List<SavePointQuery> queries);
}
