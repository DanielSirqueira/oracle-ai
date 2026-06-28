import 'dart:async';
import 'dart:io';

import 'package:oracle_core/oracle_core.dart';
import 'package:oracle_server/oracle_server.dart';

/// Oracle AI entrypoint.
///
/// Modes (first matching arg wins; default runs everything):
///   oracle_ai               # migrate + hooks HTTP + scheduler + MCP (stdio) — all-in-one
///   oracle_ai migrate       # migrate only, then exit
///   oracle_ai serve-hooks   # migrate + hooks HTTP + scheduler, block forever (shared daemon)
///   oracle_ai serve-mcp     # migrate + MCP (stdio) only — no hooks (the daemon owns them)
///   oracle_ai install-mcp [binary-path]   # print the .mcp.json snippet
///   oracle_ai install-hooks               # print the settings.json hooks snippet
///
/// Environment (see .env / .env.example): ORACLE_DB_*, ORACLE_MIGRATIONS_DIR,
/// ORACLE_DB_AUTO_CREATE, ORACLE_HTTP_HOST/PORT, ORACLE_MAINTENANCE_*.
Future<void> main(List<String> args) async {
  final env = loadEnv();

  // Config generators (no DB needed) — print client wiring and exit.
  if (args.contains('install-mcp')) {
    final i = args.indexOf('install-mcp');
    printInstallMcp(command: i + 1 < args.length ? args[i + 1] : null);
    return;
  }
  if (args.contains('install-hooks')) {
    printInstallHooks(
      host: env['ORACLE_HTTP_HOST'] ?? '127.0.0.1',
      port: int.tryParse(env['ORACLE_HTTP_PORT'] ?? '') ?? 49500,
    );
    return;
  }

  final autoCreate = (env['ORACLE_DB_AUTO_CREATE'] ?? 'false').toLowerCase() == 'true';
  final mode = _mode(args);

  final bootstrap = Bootstrap.fromEnv(env);
  Database? database;
  try {
    database = await bootstrap.start(ensureDatabase: autoCreate);
    if (mode == _Mode.migrate) {
      stderr.writeln('[oracle] migrate-only: done.');
      return;
    }

    final runHooks = mode == _Mode.hooks || mode == _Mode.all;
    final runMcp = mode == _Mode.mcp || mode == _Mode.all;

    HooksServer? hooks;
    MaintenanceScheduler? scheduler;
    if (runHooks) {
      hooks = HooksServer(
        host: env['ORACLE_HTTP_HOST'] ?? '127.0.0.1',
        port: int.tryParse(env['ORACLE_HTTP_PORT'] ?? '') ?? 49500,
      );
      try {
        await hooks.start();
        stderr.writeln('[oracle] hooks HTTP on ${hooks.host}:${hooks.port}');
      } on SocketException catch (e) {
        // Expected in multi-agent: another process already owns the port.
        stderr.writeln('[oracle] hooks HTTP not started (port in use?): '
            '${e.osError?.message ?? e.message}');
        hooks = null;
      }
      final intervalMin = int.tryParse(env['ORACLE_MAINTENANCE_INTERVAL_MINUTES'] ?? '') ?? 0;
      scheduler = MaintenanceScheduler(interval: Duration(minutes: intervalMin))..start();
    }

    if (runMcp) {
      stderr.writeln('[oracle] MCP server (stdio) ready.');
      await OracleMcpServer().serveStdio(); // blocks until stdin EOF
      stderr.writeln('[oracle] MCP server stopped.');
    } else {
      // Hooks daemon: stay up until the process is signalled to stop.
      stderr.writeln('[oracle] hooks daemon running — SIGINT/SIGTERM to stop.');
      await _awaitTermination();
    }

    scheduler?.stop();
    if (hooks != null) await hooks.stop();
  } on SystemFailure catch (failure) {
    stderr.writeln('[oracle] startup failed: ${failure.errorMessage}');
    exitCode = 1;
  } finally {
    await database?.dispose();
  }
}

enum _Mode { migrate, hooks, mcp, all }

_Mode _mode(List<String> args) {
  if (args.contains('migrate')) return _Mode.migrate;
  if (args.contains('serve-hooks') || args.contains('hooks')) return _Mode.hooks;
  if (args.contains('serve-mcp') || args.contains('mcp')) return _Mode.mcp;
  return _Mode.all;
}

/// Completes on SIGINT (or SIGTERM where supported — not on Windows).
Future<void> _awaitTermination() {
  final done = Completer<void>();
  void stop(ProcessSignal _) {
    if (!done.isCompleted) done.complete();
  }

  // SIGINT works on all platforms. SIGTERM is unsupported on Windows and the
  // failure surfaces ASYNCHRONOUSLY (a SignalException on the stream, not a
  // synchronous throw) — so guard on the platform AND swallow stream errors.
  ProcessSignal.sigint.watch().listen(stop, onError: (Object _) {});
  if (!Platform.isWindows) {
    ProcessSignal.sigterm.watch().listen(stop, onError: (Object _) {});
  }
  return done.future;
}
