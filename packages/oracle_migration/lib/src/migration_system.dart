import 'dart:io';

import 'package:oracle_core/oracle_core.dart';
import 'package:path/path.dart' as p;

import 'applied_migration.dart';
import 'migration.dart';
import 'migration_file.dart';
import 'migration_lock.dart';
import 'migration_run_report.dart';
import 'migration_runner.dart';
import 'migration_source.dart';
import 'migration_verify_report.dart';

/// Snapshot of the current migration state.
class MigrationSystemStatus {
  /// Migrations already applied (status=applied).
  final List<AppliedMigration> applied;

  /// Filesystem migrations not yet applied.
  final List<Migration> pending;

  const MigrationSystemStatus({required this.applied, required this.pending});
}

/// Main facade of the migration system.
///
/// Single entry point — combines [MigrationSource] (filesystem),
/// [MigrationLock] (concurrency) and [MigrationRunner] (execution).
///
/// ```dart
/// final system = MigrationSystem(database: db, migrationsDirectory: 'migrations');
/// final report = await system.up();
/// if (!report.success) print('Failed at ${report.failed?.name}');
/// ```
class MigrationSystem {
  /// Database connection — the internal pool manages its lifecycle.
  final Database database;

  /// Path (absolute or relative) of the migrations root folder.
  final String migrationsDirectory;

  /// Identifier of the process holding the lock (default: pid + hostname).
  final String? lockOwner;

  /// In-memory migrations (e.g. embedded in the binary). When provided, the
  /// filesystem under [migrationsDirectory] is NOT scanned — the migration set
  /// is internal and needs no configuration.
  final List<Migration>? migrations;

  MigrationSystem({
    required this.database,
    this.migrationsDirectory = 'migrations',
    this.lockOwner,
    this.migrations,
  });

  Future<List<Migration>> _discover() async =>
      migrations ?? await MigrationSource(migrationsDirectory: migrationsDirectory).discover();

  /// Applies pending migrations.
  ///
  /// - [atomic]: true = all in one transaction (full rollback on any failure).
  /// - [dryRun]: true = report only, no DB writes.
  Future<MigrationRunReport> up({bool atomic = false, bool dryRun = false}) async {
    final all = await _discover();

    final lock = MigrationLock(database: database);
    await lock.ensureTable();

    final runner = MigrationRunner(database: database);
    await runner.ensureSchema();

    return lock.withLock(
      owner: _owner(),
      action: () => runner.up(all, atomic: atomic, dryRun: dryRun),
    );
  }

  /// Snapshot of what is applied and what is pending.
  Future<MigrationSystemStatus> status() async {
    final all = await _discover();

    final runner = MigrationRunner(database: database);
    await runner.ensureSchema();

    final applied = await runner.applied();
    final pending = await runner.pending(all);
    return MigrationSystemStatus(applied: applied, pending: pending);
  }

  /// Verifies integrity (checksums, filesystem presence, pending).
  Future<MigrationVerifyReport> verify() async {
    final all = await _discover();
    final runner = MigrationRunner(database: database);
    await runner.ensureSchema();
    return runner.verify(all);
  }

  /// Full history (including failed/running) from `_migrations`.
  Future<List<AppliedMigration>> history() async {
    final runner = MigrationRunner(database: database);
    await runner.ensureSchema();
    return runner.history();
  }

  /// Scaffolds a new migration folder `v{version}/{seq}_{name}/` with an empty
  /// first file ready to edit. [sequence] is auto-incremented if omitted.
  Future<Migration> createMigration({
    required String version,
    required String name,
    int? sequence,
  }) async {
    _validateVersion(version);
    _validateName(name);

    final versionDir = Directory(p.join(migrationsDirectory, 'v$version'));
    await versionDir.create(recursive: true);

    final nextSeq = sequence ?? _nextDirSequence(versionDir);
    final seqStr = nextSeq.toString().padLeft(3, '0');
    final migrationDir = Directory(p.join(versionDir.path, '${seqStr}_$name'));
    if (migrationDir.existsSync()) {
      throw StateError('Migration ${migrationDir.path} already exists');
    }
    await migrationDir.create();

    final firstFile = File(p.join(migrationDir.path, '001_${name}_step.sql'));
    await firstFile.writeAsString(
      '-- v$version / ${seqStr}_$name / 001\n'
      '-- write your SQL here\n',
    );

    final source = MigrationSource(migrationsDirectory: migrationsDirectory);
    final all = await source.discover();
    return all.firstWhere(
      (m) => m.version == version && m.sequence == seqStr,
      orElse: () => throw StateError('Created migration not found after scan'),
    );
  }

  /// Creates a new SQL file inside an existing migration.
  Future<MigrationFile> createFileInMigration({
    required String migrationId,
    required String name,
    int? sequence,
  }) async {
    _validateName(name);

    final parts = migrationId.split('/');
    if (parts.length != 2) {
      throw ArgumentError('Invalid migrationId: $migrationId');
    }
    final dir = Directory(p.join(migrationsDirectory, parts[0], parts[1]));
    if (!dir.existsSync()) {
      throw ArgumentError('Migration does not exist: ${dir.path}');
    }

    final nextSeq = sequence ?? _nextFileSequence(dir);
    final seqStr = nextSeq.toString().padLeft(3, '0');
    final file = File(p.join(dir.path, '${seqStr}_$name.sql'));
    if (file.existsSync()) {
      throw StateError('File ${file.path} already exists');
    }
    await file.writeAsString('-- ${seqStr}_$name\n');

    return MigrationFile(
      sequence: seqStr,
      name: '${seqStr}_$name.sql',
      path: file.path,
      content: await file.readAsString(),
    );
  }

  // ===========================================================================
  // Private helpers
  // ===========================================================================

  String _owner() => lockOwner ?? 'pid-$pid@${Platform.localHostname}';

  static final _versionRegex = RegExp(r'^\d+\.\d+\.\d+$');
  static final _nameRegex = RegExp(r'^[a-zA-Z0-9_]+$');

  void _validateVersion(String v) {
    if (!_versionRegex.hasMatch(v)) {
      throw ArgumentError('Invalid version: "$v". Use semver (1.0.0).');
    }
  }

  void _validateName(String n) {
    if (!_nameRegex.hasMatch(n)) {
      throw ArgumentError('Invalid name: "$n". Use letters/digits/underscore (snake_case).');
    }
  }

  int _nextDirSequence(Directory versionDir) {
    var max = 0;
    for (final entity in versionDir.listSync()) {
      if (entity is! Directory) continue;
      final match = RegExp(r'^(\d+)[-_].+$').firstMatch(p.basename(entity.path));
      if (match != null) {
        final s = int.parse(match.group(1)!);
        if (s > max) max = s;
      }
    }
    return max + 1;
  }

  int _nextFileSequence(Directory migrationDir) {
    var max = 0;
    for (final entity in migrationDir.listSync()) {
      if (entity is! File) continue;
      final match = RegExp(r'^(\d+)[-_].+\.sql$').firstMatch(p.basename(entity.path));
      if (match != null) {
        final s = int.parse(match.group(1)!);
        if (s > max) max = s;
      }
    }
    return max + 1;
  }

  // ===========================================================================
  // Database lifecycle (create, drop, reset) — uses DatabaseConfig from core.
  // ===========================================================================

  /// Validates a database name — only letters, digits and underscore. Prevents
  /// SQL injection in `CREATE DATABASE "..."`, which cannot be parameterized.
  static final _dbNameRegex = RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*$');

  static void _validateDatabaseName(String name) {
    if (!_dbNameRegex.hasMatch(name)) {
      throw ArgumentError(
        'Invalid database name: "$name". Use only letters, digits and underscore.',
      );
    }
  }

  static Database _buildAdmin(DatabaseConfig config, String adminDatabase) =>
      PostgreSQLDatabase.fromConfig(config.copyWith(database: adminDatabase));

  /// Creates a new database (connecting to [adminDatabase], default `postgres`).
  static Future<void> createDatabase({
    required DatabaseConfig config,
    String adminDatabase = 'postgres',
  }) async {
    _validateDatabaseName(config.database);
    final admin = _buildAdmin(config, adminDatabase);
    try {
      await admin.executeUpdate(SqlStatement('CREATE DATABASE "${config.database}"'));
    } finally {
      await admin.dispose();
    }
  }

  /// Drops an existing database. Throws if it does not exist.
  static Future<void> dropDatabase({
    required DatabaseConfig config,
    String adminDatabase = 'postgres',
  }) async {
    _validateDatabaseName(config.database);
    final admin = _buildAdmin(config, adminDatabase);
    try {
      await admin.executeUpdate(SqlStatement('DROP DATABASE "${config.database}"'));
    } finally {
      await admin.dispose();
    }
  }

  /// Drops a database if it exists — no-op otherwise.
  static Future<void> dropDatabaseIfExists({
    required DatabaseConfig config,
    String adminDatabase = 'postgres',
  }) async {
    _validateDatabaseName(config.database);
    final admin = _buildAdmin(config, adminDatabase);
    try {
      await admin.executeUpdate(SqlStatement('DROP DATABASE IF EXISTS "${config.database}"'));
    } finally {
      await admin.dispose();
    }
  }

  /// True if [config.database] exists on the server.
  static Future<bool> databaseExists({
    required DatabaseConfig config,
    String adminDatabase = 'postgres',
  }) async {
    _validateDatabaseName(config.database);
    final admin = _buildAdmin(config, adminDatabase);
    try {
      final result = await admin.select(SqlStatement(
        'SELECT 1 FROM pg_database WHERE datname = :name',
        {'name': config.database},
      ));
      return result.rows.isNotEmpty;
    } finally {
      await admin.dispose();
    }
  }

  /// Resets a database: drop if present, create fresh, apply all migrations.
  /// Use with extreme caution — it destroys data.
  static Future<MigrationRunReport> resetDatabase({
    required DatabaseConfig config,
    required String migrationsDirectory,
    String adminDatabase = 'postgres',
    bool atomic = false,
  }) async {
    _validateDatabaseName(config.database);
    await dropDatabaseIfExists(config: config, adminDatabase: adminDatabase);
    await createDatabase(config: config, adminDatabase: adminDatabase);

    final db = PostgreSQLDatabase.fromConfig(config);
    try {
      final system = MigrationSystem(database: db, migrationsDirectory: migrationsDirectory);
      return await system.up(atomic: atomic);
    } finally {
      await db.dispose();
    }
  }

  /// Creates the database if missing, then applies migrations. Setup helper.
  static Future<MigrationRunReport> initDatabase({
    required DatabaseConfig config,
    required String migrationsDirectory,
    String adminDatabase = 'postgres',
    bool atomic = false,
  }) async {
    _validateDatabaseName(config.database);
    final exists = await databaseExists(config: config, adminDatabase: adminDatabase);
    if (!exists) {
      await createDatabase(config: config, adminDatabase: adminDatabase);
    }
    final db = PostgreSQLDatabase.fromConfig(config);
    try {
      final system = MigrationSystem(database: db, migrationsDirectory: migrationsDirectory);
      return await system.up(atomic: atomic);
    } finally {
      await db.dispose();
    }
  }
}
