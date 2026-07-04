import 'dart:async';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:oracle_core/oracle_core.dart';

/// Provisions a local PostgreSQL + pgvector for users WITHOUT Docker.
///
/// Strategy (mirrors the setup wizard's database step):
/// 1. [canConnect] — an existing PostgreSQL is always preferred.
/// 2. [dockerAvailable] — compose users keep the compose path.
/// 3. [provisionPortable] — extract the official portable binaries zip +
///    a prebuilt pgvector, `initdb` a data directory, pick a free port and
///    start it with `pg_ctl`. No admin rights, no installer, no Docker.
///
/// The caller (wizard) downloads the two zips (with progress UI) and hands
/// their paths in; this class owns everything after that.
class PgProvisioner {
  const PgProvisioner();

  /// True when a PostgreSQL answers `SELECT 1` with [config]'s credentials.
  static Future<bool> canConnect(DatabaseConfig config) async {
    // Probe the admin DB: on a fresh server the app database may not exist yet.
    final probe = PostgreSQLDatabase.fromConfig(config.copyWith(database: 'postgres'));
    try {
      await probe.select(const SqlStatement('SELECT 1 AS ok', {}));
      return true;
    } catch (_) {
      return false;
    } finally {
      await probe.dispose();
    }
  }

  /// True when a usable Docker CLI is on PATH (daemon responding).
  static Future<bool> dockerAvailable() async {
    try {
      final result = await Process.run('docker', ['info', '--format', '{{.ServerVersion}}'])
          .timeout(const Duration(seconds: 10));
      return result.exitCode == 0 && '${result.stdout}'.trim().isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// First free TCP port at/after [start] (checked by binding on loopback).
  static Future<int> findFreePort({int start = 5433}) async {
    for (var port = start; port < start + 200; port++) {
      try {
        final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
        await socket.close();
        return port;
      } on SocketException {
        continue; // busy — try the next one
      }
    }
    throw const SocketException('no free port found');
  }

  /// Extracts the portable binaries + pgvector, initializes a cluster and
  /// starts it. Idempotent-ish: an already-extracted [installDir] is reused;
  /// an existing [dataDir] with a cluster is started instead of re-initialized.
  Future<PgProvisionResult> provisionPortable({
    required String installDir,
    required String dataDir,
    required String pgZip,
    required String pgvectorZip,
    required String password,
    String superuser = 'postgres',
    int? port,
    void Function(String step)? onStep,
  }) async {
    void step(String s) => onStep?.call(s);

    // 1) Portable binaries. The official zip has a single `pgsql/` root.
    final pgRoot = Directory('$installDir${Platform.pathSeparator}pgsql');
    final binDir = '${pgRoot.path}${Platform.pathSeparator}bin';
    if (!File('$binDir${Platform.pathSeparator}pg_ctl.exe').existsSync()) {
      step('Extracting portable PostgreSQL…');
      await extractFileToDisk(pgZip, installDir);
      if (!File('$binDir${Platform.pathSeparator}pg_ctl.exe').existsSync()) {
        throw PgProvisionFailure('pg_ctl.exe not found after extracting $pgZip');
      }
    }

    // 2) pgvector: vector.dll -> lib/, vector.control + vector--*.sql ->
    //    share/extension/. Release zips vary in layout, so route by filename.
    step('Installing pgvector…');
    await _installPgvector(pgvectorZip, pgRoot.path);

    // 3) initdb (skip when the cluster already exists).
    final data = Directory(dataDir);
    final pgVersionFile = File('$dataDir${Platform.pathSeparator}PG_VERSION');
    if (!pgVersionFile.existsSync()) {
      step('Initializing the cluster (initdb)…');
      await data.create(recursive: true);
      final pwFile = File('$installDir${Platform.pathSeparator}.pw.tmp');
      await pwFile.writeAsString(password, flush: true);
      try {
        await _run(binDir, 'initdb.exe', [
          '-D', dataDir,
          '-U', superuser,
          '--auth=scram-sha-256',
          '--pwfile=${pwFile.path}',
          '--encoding=UTF8',
          '--locale=C',
        ]);
      } finally {
        await pwFile.delete();
      }
    }

    // 4) If the cluster is ALREADY running (e.g. a previous interrupted run),
    //    adopt its live port from postmaster.pid — reconfiguring a running
    //    server would make us probe a port nobody listens on. Otherwise pick
    //    a free port, persist it in postgresql.conf and start.
    final int chosenPort;
    final status = await Process.run('$binDir${Platform.pathSeparator}pg_ctl.exe',
        ['status', '-D', dataDir]);
    if (status.exitCode == 0) {
      final pidFile = File('$dataDir${Platform.pathSeparator}postmaster.pid');
      final lines = await pidFile.readAsLines();
      chosenPort = int.parse(lines[3].trim()); // line 4 of postmaster.pid = port
      step('Cluster already running — adopting port $chosenPort.');
    } else {
      chosenPort = port ?? await findFreePort();
      step('Configuring port $chosenPort…');
      final conf = File('$dataDir${Platform.pathSeparator}postgresql.conf');
      var text = await conf.readAsString();
      text = text.replaceAll(
          RegExp(r'^#?port\s*=\s*\d+', multiLine: true), 'port = $chosenPort');
      if (!text.contains('port = $chosenPort')) text = '$text\nport = $chosenPort\n';
      await conf.writeAsString(text, flush: true);

      step('Starting PostgreSQL…');
      await _run(binDir, 'pg_ctl.exe', [
        'start',
        '-D', dataDir,
        '-l', '$installDir${Platform.pathSeparator}postgres.log',
        '-w', '-t', '60',
      ]);
    }

    // 6) Verify it answers.
    final config = DatabaseConfig(
      host: 'localhost',
      port: chosenPort,
      user: superuser,
      password: password,
      database: 'postgres',
    );
    if (!await canConnect(config)) {
      throw PgProvisionFailure(
          'PostgreSQL started but did not answer at localhost:$chosenPort');
    }
    step('PostgreSQL ready at localhost:$chosenPort.');
    return PgProvisionResult(binDir: binDir, dataDir: dataDir, port: chosenPort);
  }

  /// Stops a portable cluster (wizard rollback / uninstall).
  Future<void> stop({required String binDir, required String dataDir}) async {
    await Process.run('$binDir${Platform.pathSeparator}pg_ctl.exe',
        ['stop', '-D', dataDir, '-m', 'fast', '-w', '-t', '30']);
  }

  /// Copies pgvector artifacts out of [zipPath] into the PG tree, routing each
  /// file by name so any release layout works.
  Future<void> _installPgvector(String zipPath, String pgRoot) async {
    final sep = Platform.pathSeparator;
    final tmp = Directory('$pgRoot$sep.pgvector.tmp');
    if (await tmp.exists()) await tmp.delete(recursive: true);
    await extractFileToDisk(zipPath, tmp.path);

    var dll = 0, control = 0, sql = 0;
    await for (final f in tmp.list(recursive: true)) {
      if (f is! File) continue;
      final name = f.uri.pathSegments.last;
      if (name == 'vector.dll') {
        await f.copy('$pgRoot${sep}lib$sep$name');
        dll++;
      } else if (name.endsWith('.control')) {
        await f.copy('$pgRoot${sep}share${sep}extension$sep$name');
        control++;
      } else if (name.startsWith('vector--') && name.endsWith('.sql')) {
        await f.copy('$pgRoot${sep}share${sep}extension$sep$name');
        sql++;
      }
    }
    await tmp.delete(recursive: true);
    if (dll == 0 || control == 0 || sql == 0) {
      throw PgProvisionFailure(
          'pgvector incompleto no zip (dll=$dll control=$control sql=$sql)');
    }
  }

  Future<void> _run(String binDir, String exe, List<String> args) async {
    final result = await Process.run('$binDir${Platform.pathSeparator}$exe', args);
    if (result.exitCode != 0) {
      throw PgProvisionFailure(
          '$exe falhou (${result.exitCode}): ${result.stderr}\n${result.stdout}');
    }
  }
}

class PgProvisionResult {
  final String binDir;
  final String dataDir;
  final int port;
  const PgProvisionResult({required this.binDir, required this.dataDir, required this.port});
}

class PgProvisionFailure implements Exception {
  final String message;
  const PgProvisionFailure(this.message);
  @override
  String toString() => 'PgProvisionFailure: $message';
}
