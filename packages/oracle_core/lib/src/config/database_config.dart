import 'dart:io';

/// Connection settings for the Oracle AI database.
///
/// Built from environment variables ([DatabaseConfig.fromEnv]) so the MCP
/// server and the migration runner share one source of truth.
class DatabaseConfig {
  final String host;
  final int port;
  final String user;
  final String password;
  final String database;
  final bool useSsl;
  final bool useCompression;

  const DatabaseConfig({
    required this.host,
    required this.port,
    required this.user,
    required this.password,
    required this.database,
    this.useSsl = false,
    this.useCompression = false,
  });

  /// Reads the configuration from environment variables, falling back to local
  /// development defaults.
  ///
  /// | Variable               | Default      |
  /// |------------------------|--------------|
  /// | `ORACLE_DB_HOST`       | `localhost`  |
  /// | `ORACLE_DB_PORT`       | `5432`       |
  /// | `ORACLE_DB_USER`       | `postgres`   |
  /// | `ORACLE_DB_PASSWORD`   | `postgres`   |
  /// | `ORACLE_DB_NAME`       | `oracle_db`  |
  /// | `ORACLE_DB_SSL`        | `false`      |
  factory DatabaseConfig.fromEnv([Map<String, String>? env]) {
    final e = env ?? Platform.environment;
    // Treat an empty value as "not set" so blank entries fall back to defaults.
    String pick(String key, String fallback) {
      final v = e[key];
      return (v == null || v.trim().isEmpty) ? fallback : v;
    }

    return DatabaseConfig(
      host: pick('ORACLE_DB_HOST', 'localhost'),
      port: int.tryParse(e['ORACLE_DB_PORT'] ?? '') ?? 5432,
      user: pick('ORACLE_DB_USER', 'postgres'),
      password: pick('ORACLE_DB_PASSWORD', 'postgres'),
      database: pick('ORACLE_DB_NAME', 'oracle_db'),
      useSsl: (e['ORACLE_DB_SSL'] ?? 'false').toLowerCase() == 'true',
    );
  }

  DatabaseConfig copyWith({
    String? host,
    int? port,
    String? user,
    String? password,
    String? database,
    bool? useSsl,
    bool? useCompression,
  }) {
    return DatabaseConfig(
      host: host ?? this.host,
      port: port ?? this.port,
      user: user ?? this.user,
      password: password ?? this.password,
      database: database ?? this.database,
      useSsl: useSsl ?? this.useSsl,
      useCompression: useCompression ?? this.useCompression,
    );
  }

  @override
  String toString() =>
      'DatabaseConfig($user@$host:$port/$database, ssl: $useSsl)';
}
