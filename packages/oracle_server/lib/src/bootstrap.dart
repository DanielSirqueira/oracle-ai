import 'dart:io';

import 'package:oracle_core/oracle_core.dart';
import 'package:oracle_memory/oracle_memory.dart';
import 'package:oracle_migration/oracle_migration.dart';

import 'backup/db_backup_service.dart';
import 'migrations/embedded_migrations.dart';

/// Brings the process up: resolves configuration, registers core dependencies
/// in DI, and applies pending database migrations.
///
/// Intended to run once on MCP server startup.
class Bootstrap {
  /// Database connection settings (defaults to [DatabaseConfig.fromEnv]).
  final DatabaseConfig config;

  /// Embedding provider (defaults to a local, offline embedder).
  final Embedder embedder;

  /// When true, run the deterministic maintenance sweep once after migrations
  /// (opt-in via `ORACLE_MAINTENANCE_ON_STARTUP=true`). Off by default so a
  /// restart never silently forgets memories.
  final bool maintenanceOnStartup;

  /// Path to a portable data seed to restore when the database is empty (see
  /// [DbBackupService]). Null disables seed-on-boot. Opt-in: unset by default so
  /// a host process never restores from a stray file — docker-compose sets it.
  final String? seedPath;

  /// Whether seed-on-boot is allowed at all (env `ORACLE_DB_SEED_ON_EMPTY`,
  /// default true). Restore still only fires when the DB is actually empty.
  final bool seedOnEmpty;

  Bootstrap({
    DatabaseConfig? config,
    Embedder? embedder,
    this.maintenanceOnStartup = false,
    this.seedPath,
    this.seedOnEmpty = true,
  })  : config = config ?? DatabaseConfig.fromEnv(),
        embedder = embedder ?? LocalEmbedder();

  /// Builds a [Bootstrap] from a merged environment map (see [loadEnv]).
  factory Bootstrap.fromEnv(Map<String, String> env) {
    final seed = env['ORACLE_DB_SEED_PATH']?.trim();
    return Bootstrap(
      config: DatabaseConfig.fromEnv(env),
      embedder: createEmbedder(EmbeddingConfig.fromEnv(env)),
      maintenanceOnStartup:
          (env['ORACLE_MAINTENANCE_ON_STARTUP'] ?? 'false').toLowerCase() == 'true',
      seedPath: (seed == null || seed.isEmpty) ? null : seed,
      seedOnEmpty: (env['ORACLE_DB_SEED_ON_EMPTY'] ?? 'true').toLowerCase() == 'true',
    );
  }

  /// Builds the [Database], registers it as a DI singleton, and runs pending
  /// migrations. Returns the live [Database] (the caller owns its lifecycle).
  ///
  /// When [ensureDatabase] is true, the target database is created if it does
  /// not exist yet (requires access to the `postgres` admin database).
  Future<Database> start({bool ensureDatabase = false, bool allowSeed = false}) async {
    stderr.writeln('[oracle] starting — $config');

    if (ensureDatabase) {
      final exists = await MigrationSystem.databaseExists(config: config);
      if (!exists) {
        stderr.writeln('[oracle] database "${config.database}" not found — creating it');
        await MigrationSystem.createDatabase(config: config);
      }
    }

    final database = PostgreSQLDatabase.fromConfig(config);
    _registerCore(database);

    final report = await runMigrations(database);
    _logReport(report);
    if (!report.success) {
      throw MigrationFailure(
        errorMessage: 'Startup migration failed at '
            '${report.failed?.migrationId}: ${report.failed?.errorMessage}',
        stackTrace: StackTrace.current,
      );
    }

    // Seed a fresh (empty) database from a portable data backup, so bringing the
    // stack up on a new volume restores the saved memory bank. Only in the modes
    // that own boot ([allowSeed]) — a per-agent MCP never seeds, avoiding a
    // cold-start race — and only when the DB is empty (never overwrites data).
    if (allowSeed && seedOnEmpty && seedPath != null) {
      await _maybeSeed(database, seedPath!);
    }

    if (maintenanceOnStartup) {
      await _runStartupMaintenance();
    }

    return database;
  }

  /// Restores the data seed when the database is empty. A bad or missing seed is
  /// logged but never bricks startup — the daemon comes up on the empty DB.
  Future<void> _maybeSeed(Database database, String path) async {
    try {
      final report = await DbBackupService(database).restore(path);
      stderr.writeln(report.restored
          ? '[oracle] seed restored from $path — ${report.rows} rows'
          : '[oracle] seed skipped (${report.reason}) — $path');
    } catch (error) {
      stderr.writeln('[oracle] seed restore FAILED ($path): $error');
    }
  }

  /// Opt-in deterministic sweep (decay + dedup of memories) with default policy.
  Future<void> _runStartupMaintenance() async {
    final result = await injector.get<RunMaintenanceUsecase>()(const DecayPolicy());
    result.fold(
      (r) => stderr.writeln(
        '[oracle] maintenance: decayed=${r.decayedCount} deduped=${r.dedupedCount}',
      ),
      (f) => stderr.writeln('[oracle] maintenance FAILED: ${f.errorMessage}'),
    );
  }

  /// Applies all pending migrations. Safe to call repeatedly. The migration set
  /// is **embedded in the binary** — no filesystem or configuration needed; on
  /// startup Oracle applies only what the DB ledger is missing.
  ///
  /// Tolerant of concurrent startup (common with multiple agents: Claude Code,
  /// Codex, ...): if another process holds the migration lock, retry with a
  /// short backoff — the holder applies the (fast) migrations and releases,
  /// after which this process acquires, finds nothing pending, and returns.
  Future<MigrationRunReport> runMigrations(Database database) async {
    final system = MigrationSystem(
      database: database,
      migrations: embeddedMigrations(),
    );
    const maxAttempts = 20;
    for (var attempt = 1;; attempt++) {
      try {
        return await system.up();
      } on MigrationLockHeldFailure catch (failure) {
        if (attempt >= maxAttempts) rethrow;
        stderr.writeln(
          '[oracle] migration lock held (${failure.errorMessage}) — '
          'retry $attempt/$maxAttempts',
        );
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }
  }

  void _registerCore(Database database) {
    injector.addInstance<Database>(database);
    injector.addInstance<Embedder>(embedder);
    // Register feature modules (Datasource → Repository → UseCases), then commit.
    registerModules([
      ProductModule(),
      ProjectModule(),
      ArchitectureModule(),
      RuleModule(),
      SkillModule(),
      MemoryModule(),
      CaptureModule(),
      HandoffModule(),
      MaintenanceModule(),
      MetricsModule(),
    ]);
  }

  void _logReport(MigrationRunReport report) {
    final status = report.success
        ? 'ok'
        : 'FAILED at ${report.failed?.migrationId}';
    stderr.writeln(
      '[oracle] migrations: applied=${report.applied.length} '
      'skipped=${report.skipped.length} — $status',
    );
  }
}
