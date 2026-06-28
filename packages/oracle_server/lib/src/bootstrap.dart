import 'dart:io';

import 'package:oracle_core/oracle_core.dart';
import 'package:oracle_memory/oracle_memory.dart';
import 'package:oracle_migration/oracle_migration.dart';

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

  Bootstrap({
    DatabaseConfig? config,
    Embedder? embedder,
    this.maintenanceOnStartup = false,
  })  : config = config ?? DatabaseConfig.fromEnv(),
        embedder = embedder ?? LocalEmbedder();

  /// Builds a [Bootstrap] from a merged environment map (see [loadEnv]).
  factory Bootstrap.fromEnv(Map<String, String> env) {
    return Bootstrap(
      config: DatabaseConfig.fromEnv(env),
      embedder: createEmbedder(EmbeddingConfig.fromEnv(env)),
      maintenanceOnStartup:
          (env['ORACLE_MAINTENANCE_ON_STARTUP'] ?? 'false').toLowerCase() == 'true',
    );
  }

  /// Builds the [Database], registers it as a DI singleton, and runs pending
  /// migrations. Returns the live [Database] (the caller owns its lifecycle).
  ///
  /// When [ensureDatabase] is true, the target database is created if it does
  /// not exist yet (requires access to the `postgres` admin database).
  Future<Database> start({bool ensureDatabase = false}) async {
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

    if (maintenanceOnStartup) {
      await _runStartupMaintenance();
    }

    return database;
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
