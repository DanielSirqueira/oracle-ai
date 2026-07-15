import 'dart:async';
import 'dart:convert';
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
///   oracle_ai forward-hook [--agent id]   # relay a stdin hook event to the receiver
///                                         # (bridge for command-only agent hooks)
///   oracle_ai backup-db [path]            # write a portable data seed, then exit
///   oracle_ai restore-db [path] [--force] # restore a data seed (only if empty, unless --force)
///   oracle_ai sync-skills [dir]           # materialize the central skill library to
///                                         # `dir/key/SKILL.md` (default ~/.claude/skills)
///
/// Environment (see .env / .env.example): ORACLE_DB_*, ORACLE_MIGRATIONS_DIR,
/// ORACLE_DB_AUTO_CREATE, ORACLE_HTTP_HOST/PORT, ORACLE_MAINTENANCE_*.
Future<void> main(List<String> args) async {
  // Config resolution: cwd .env (repo/dev flow) → .env NEXT TO THE BINARY
  // (installed flow: agents spawn the MCP with cwd at THEIR project, while
  // the installer writes .env beside oracle_ai.exe in the program folder).
  final exeEnv = '${File(Platform.resolvedExecutable).parent.path}'
      '${Platform.pathSeparator}.env';
  final env = loadEnv(path: File('.env').existsSync() ? '.env' : exeEnv);

  // Config generators (no DB needed) — print client wiring and exit.
  if (args.contains('install-mcp')) {
    final i = args.indexOf('install-mcp');
    printInstallMcp(command: i + 1 < args.length ? args[i + 1] : null);
    return;
  }
  if (args.contains('install-hooks')) {
    printInstallHooks(
      host: env['ORACLE_HTTP_HOST'] ?? '127.0.0.1',
      port: int.tryParse(env['ORACLE_HTTP_PORT'] ?? '') ?? 47500,
      token: env['ORACLE_HOOK_TOKEN'],
    );
    return;
  }
  // Bridge for agents whose hooks run a COMMAND (not native HTTP) — Codex,
  // Cursor, Gemini CLI, VS Code. They pipe the event JSON on our stdin; we relay
  // it to the local hook receiver and echo the receiver's reply on stdout (so
  // inject-style hooks still get their context). ALWAYS exit 0 and never hang —
  // a down receiver must not block the agent.
  if (args.contains('forward-hook')) {
    await _runForwardHook(args, env);
    return;
  }

  final autoCreate = (env['ORACLE_DB_AUTO_CREATE'] ?? 'false').toLowerCase() == 'true';

  // Backup / restore: DB ops that connect, run, and exit (no serving).
  if (args.contains('backup-db') || args.contains('restore-db')) {
    await _runBackupCli(args, env, autoCreate);
    return;
  }
  if (args.contains('sync-skills')) {
    await _runSyncSkills(args, env, autoCreate);
    return;
  }

  final mode = _mode(args);
  // Only the boot-owning modes (daemon / all-in-one) may restore a seed on an
  // empty DB; a per-agent `serve-mcp` never seeds (avoids a cold-start race).
  final allowSeed = mode == _Mode.hooks || mode == _Mode.all;

  final bootstrap = Bootstrap.fromEnv(env);
  Database? database;
  try {
    database = await bootstrap.start(ensureDatabase: autoCreate, allowSeed: allowSeed);
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
        port: int.tryParse(env['ORACLE_HTTP_PORT'] ?? '') ?? 47500,
        // Config comes from the merged .env map (loadEnv), NOT Platform.environment
        // — a `.env`-only ORACLE_HOOK_TOKEN would otherwise be silently ignored and
        // the endpoint would accept unauthenticated writes while looking protected.
        hookToken: env['ORACLE_HOOK_TOKEN'],
        metricsEnabled: env['ORACLE_METRICS_ENABLED'] == null
            ? null
            : env['ORACLE_METRICS_ENABLED']!.toLowerCase() == 'true',
        metricsLabel: env['ORACLE_METRICS_LABEL'],
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

/// Relays a hook event to the local receiver on behalf of a command-only agent.
///
/// Reads the event JSON from stdin, tags it with the agent name (`--agent <id>`,
/// default `unknown`) when the payload doesn't already carry one, POSTs it to
/// `http://HOST:PORT/hook` with the bearer token, and writes the receiver's body
/// to stdout. Every failure path is swallowed and the process still exits 0:
/// hooks sit in the agent's critical path, so the bridge must be invisible when
/// the daemon is down or slow.
Future<void> _runForwardHook(List<String> args, Map<String, String> env) async {
  try {
    final ai = args.indexOf('--agent');
    final agent = (ai >= 0 && ai + 1 < args.length) ? args[ai + 1] : 'unknown';
    final host = env['ORACLE_HTTP_HOST'] ?? '127.0.0.1';
    final port = int.tryParse(env['ORACLE_HTTP_PORT'] ?? '') ?? 47500;
    final token = env['ORACLE_HOOK_TOKEN']?.trim();

    final raw = await stdin.fold<List<int>>(<int>[], (acc, chunk) => acc..addAll(chunk));

    // Inject the agent id so capture attributes the session correctly, but only
    // when the payload is a JSON object missing one — otherwise forward verbatim.
    List<int> body = raw;
    try {
      final decoded = jsonDecode(utf8.decode(raw));
      if (decoded is Map<String, dynamic> && (decoded['agent'] == null)) {
        decoded['agent'] = agent;
        body = utf8.encode(jsonEncode(decoded));
      }
    } catch (_) {/* not JSON (or empty) — relay the raw bytes */}

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
    try {
      final req = await client.postUrl(Uri.parse('http://$host:$port/hook'));
      req.headers.contentType = ContentType.json;
      if (token != null && token.isNotEmpty) {
        req.headers.set('Authorization', 'Bearer $token');
      }
      req.add(body);
      final resp = await req.close().timeout(const Duration(seconds: 6));
      final reply = await resp.transform(utf8.decoder).join();
      if (reply.isNotEmpty) stdout.write(reply);
    } finally {
      client.close(force: true);
    }
  } catch (_) {
    // Never surface a bridge failure to the agent.
  }
}

/// Runs `backup-db` / `restore-db`: connect (migrate), perform the op, exit.
Future<void> _runBackupCli(List<String> args, Map<String, String> env, bool autoCreate) async {
  final isRestore = args.contains('restore-db');
  final marker = isRestore ? 'restore-db' : 'backup-db';
  final i = args.indexOf(marker);
  final next = (i + 1 < args.length) ? args[i + 1] : null;
  final path = (next != null && !next.startsWith('-'))
      ? next
      : (env['ORACLE_DB_SEED_PATH']?.trim().isNotEmpty ?? false)
          ? env['ORACLE_DB_SEED_PATH']!.trim()
          : 'backups/oracle_seed.sql';

  final database = await Bootstrap.fromEnv(env).start(ensureDatabase: autoCreate);
  try {
    final service = DbBackupService(database);
    if (isRestore) {
      final report = await service.restore(path, force: args.contains('--force'));
      stderr.writeln(report.restored
          ? '[oracle] restored $path — ${report.rows} rows'
          : '[oracle] restore skipped (${report.reason}) — $path');
    } else {
      final report = await service.backup(path);
      stderr.writeln('[oracle] backup written: ${report.path} — '
          '${report.rows} rows, ${report.bytes} bytes');
    }
  } on SystemFailure catch (failure) {
    stderr.writeln('[oracle] ${isRestore ? "restore" : "backup"} failed: ${failure.errorMessage}');
    exitCode = 1;
  } finally {
    await database.dispose();
  }
}

/// Materializes the central skill library to `<dir>/<key>/SKILL.md` so agents
/// with native skill discovery (e.g. Claude Code scanning ~/.claude/skills)
/// pick them up without any per-agent duplication — the database stays the
/// single source of truth; this just projects it onto disk.
///
/// Sync is safe by ownership: every file written carries a `managed-by:
/// oracle-ai` frontmatter marker, and only folders bearing that marker are
/// pruned when their skill disappears — hand-written skills are never touched.
Future<void> _runSyncSkills(List<String> args, Map<String, String> env, bool autoCreate) async {
  final i = args.indexOf('sync-skills');
  final next = (i + 1 < args.length) ? args[i + 1] : null;
  final dir = (next != null && !next.startsWith('-')) ? next : null;

  final database = await Bootstrap.fromEnv(env).start(ensureDatabase: autoCreate);
  try {
    final report = await const SkillSyncService().sync(dir: dir);
    stderr.writeln('[oracle] sync-skills: ${report.synced} skill(s) -> ${report.dir} '
        '(pruned ${report.pruned} stale)');
  } on SystemFailure catch (failure) {
    stderr.writeln('[oracle] sync-skills failed: ${failure.errorMessage}');
    exitCode = 1;
  } finally {
    await database.dispose();
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
