import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:oracle_core/oracle_core.dart';
import 'package:oracle_server/oracle_server.dart';

enum OracleConnectionStatus { idle, connecting, connected, error }

/// Owns the Studio's connection to the Oracle database.
///
/// Reuses the server [Bootstrap] directly — same DI container, same usecases
/// the MCP server runs — so the Studio has no API layer of its own and can
/// never drift from the backend's behavior.
class OracleConnection extends ChangeNotifier {
  OracleConnectionStatus status = OracleConnectionStatus.idle;
  String? error;
  Database? database;

  /// The `.env` the connection was configured from (null = defaults only).
  String? envPath;

  /// The merged environment (file + process) the connection was built from —
  /// the daemon pieces (hooks port/token, maintenance interval) read it too.
  Map<String, String> env = const {};

  /// Directory of [envPath] — where relative artifacts (backups/) belong.
  String? get envDir => envPath == null ? null : File(envPath!).parent.path;

  /// Bootstrap registers into the global DI exactly once per process; retries
  /// must not re-register (auto_injector rejects duplicates).
  bool _bootstrapped = false;

  Future<void> connect() async {
    status = OracleConnectionStatus.connecting;
    error = null;
    notifyListeners();
    try {
      envPath = _findEnvFile();
      env = loadEnv(path: envPath ?? '.env');

      // Pre-flight on a throwaway pool: the common failure (DB down, wrong
      // credentials) surfaces here and stays retryable — nothing was
      // registered in DI yet.
      final probe = PostgreSQLDatabase.fromConfig(DatabaseConfig.fromEnv(env));
      try {
        await probe.select(const SqlStatement('SELECT 1 AS ok', {}));
      } finally {
        await probe.dispose();
      }

      if (!_bootstrapped) {
        database = await Bootstrap.fromEnv(env).start();
        _bootstrapped = true;
      }
      status = OracleConnectionStatus.connected;
    } catch (e) {
      error = e is SystemFailure ? e.errorMessage : '$e';
      status = OracleConnectionStatus.error;
    }
    notifyListeners();
  }

  /// Finds the `.env`: `ORACLE_ENV_PATH` wins; otherwise walk up from the
  /// executable's directory FIRST (a packaged Studio sits next to its config),
  /// then from the working directory as a dev fallback.
  ///
  /// Exe-first matters for the installed app: launching with an unrelated cwd
  /// (a shell open in some repo, or "start with Windows") must NOT let a stray
  /// `.env` there hijack the install's own config. In dev this still resolves to
  /// the repo `.env` — walking up from build/.../Release reaches the repo root
  /// too — so the order change is transparent for development.
  static String? _findEnvFile() {
    final override = Platform.environment['ORACLE_ENV_PATH'];
    if (override != null &&
        override.trim().isNotEmpty &&
        File(override).existsSync()) {
      return override;
    }
    for (final start in [
      File(Platform.resolvedExecutable).parent.path,
      Directory.current.path,
    ]) {
      var dir = Directory(start);
      // Deep enough to reach the repo root even from the built exe's folder
      // (apps/oracle_studio/build/windows/x64/runner/Release = 7 levels up).
      for (var depth = 0; depth < 10; depth++) {
        final candidate = File('${dir.path}${Platform.pathSeparator}.env');
        if (candidate.existsSync()) return candidate.path;
        final parent = dir.parent;
        if (parent.path == dir.path) break;
        dir = parent;
      }
    }
    return null;
  }
}
