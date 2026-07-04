import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:oracle_core/oracle_core.dart';
import 'package:oracle_server/oracle_server.dart';

enum DbMode { existing, docker, portable }

/// The wizard's brain: holds every choice and performs the installation using
/// the same engine code the server/Studio use (PgProvisioner, Bootstrap,
/// DbBackupService) — the wizard is only a UI over proven pieces.
class SetupState extends ChangeNotifier {
  // ── database ──
  DbMode dbMode = DbMode.existing;
  String dbHost = 'localhost';
  int dbPort = 5432;
  String dbUser = 'postgres';
  String dbPassword = 'postgres';
  String dbName = 'oracle_db';

  bool? existingOk; // null = not probed yet
  bool? dockerOk;
  bool portableReady = false;

  // ── embedder ──
  String embedderProvider = 'local';
  String embedderApiKey = '';

  // ── security ──
  String hookToken = '';

  // ── install progress ──
  final List<String> log = [];
  bool busy = false;
  bool installed = false;
  String? error;

  void _log(String s) {
    log.add(s);
    notifyListeners();
  }

  DatabaseConfig get dbConfig => DatabaseConfig(
      host: dbHost, port: dbPort, user: dbUser, password: dbPassword, database: dbName);

  /// Where the configuration lives. Prefers an existing repo .env (dev run);
  /// falls back to the per-user install dir (packaged run).
  String get envTargetPath {
    var dir = Directory.current;
    for (var i = 0; i < 10; i++) {
      if (File('${dir.path}${Platform.pathSeparator}.env').existsSync() ||
          File('${dir.path}${Platform.pathSeparator}.env.example').existsSync()) {
        return '${dir.path}${Platform.pathSeparator}.env';
      }
      if (dir.parent.path == dir.path) break;
      dir = dir.parent;
    }
    final base = Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path;
    return '$base${Platform.pathSeparator}OracleAI${Platform.pathSeparator}.env';
  }

  String get installBase {
    final base = Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path;
    return '$base${Platform.pathSeparator}OracleAI';
  }

  Future<void> detect() async {
    busy = true;
    notifyListeners();
    existingOk = await PgProvisioner.canConnect(dbConfig);
    dockerOk = await PgProvisioner.dockerAvailable();
    busy = false;
    notifyListeners();
  }

  void generateToken() {
    final rnd = Random.secure();
    hookToken =
        List.generate(32, (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    notifyListeners();
  }

  // ── portable provisioning ──

  static const _pgUrl =
      'https://get.enterprisedb.com/postgresql/postgresql-17.6-1-windows-x64-binaries.zip';
  static const _pgvectorUrl =
      'https://github.com/andreiramani/pgvector_pgsql_windows/releases/download/0.8.3_17.6/vector.v0.8.3-pg17.zip';

  /// Bundled payload (next to the exe) wins; otherwise download with progress.
  Future<String> _ensureArtifact(String url, String fileName) async {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final bundled = File('$exeDir${Platform.pathSeparator}payload'
        '${Platform.pathSeparator}$fileName');
    if (bundled.existsSync()) {
      _log('Usando payload embutido: $fileName');
      return bundled.path;
    }
    final dest = File('$installBase${Platform.pathSeparator}downloads'
        '${Platform.pathSeparator}$fileName');
    if (dest.existsSync() && dest.lengthSync() > 0) {
      _log('Já baixado: $fileName');
      return dest.path;
    }
    await dest.parent.create(recursive: true);
    _log('Baixando $fileName…');
    final client = HttpClient();
    try {
      var request = await client.getUrl(Uri.parse(url));
      request.followRedirects = true;
      request.maxRedirects = 8;
      final response = await request.close();
      if (response.statusCode != 200) {
        throw PgProvisionFailure('download $fileName falhou: HTTP ${response.statusCode}');
      }
      final total = response.contentLength;
      final sink = dest.openWrite();
      var received = 0;
      var lastPct = -10;
      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) {
          final pct = (received * 100 ~/ total);
          if (pct >= lastPct + 10) {
            lastPct = pct;
            _log('  $fileName: $pct%');
          }
        }
      }
      await sink.close();
      _log('Baixado: $fileName (${(received / (1024 * 1024)).toStringAsFixed(0)} MB)');
      return dest.path;
    } finally {
      client.close();
    }
  }

  Future<void> provisionPortable() async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      final pgZip = await _ensureArtifact(_pgUrl, 'postgresql-17.6-1-windows-x64-binaries.zip');
      final vecZip = await _ensureArtifact(_pgvectorUrl, 'vector.v0.8.3-pg17.zip');
      final sep = Platform.pathSeparator;
      final rnd = Random.secure();
      final password =
          List.generate(16, (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
      final result = await const PgProvisioner().provisionPortable(
        installDir: '$installBase${sep}pg',
        dataDir: '$installBase${sep}pgdata',
        pgZip: pgZip,
        pgvectorZip: vecZip,
        password: password,
        onStep: _log,
      );
      dbHost = 'localhost';
      dbPort = result.port;
      dbUser = 'postgres';
      dbPassword = password;
      portableReady = true;
      _log('Banco local pronto (sem Docker) em localhost:${result.port}.');
    } catch (e) {
      error = '$e';
      _log('FALHA: $e');
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  // ── apply ──

  String buildEnv() {
    final b = StringBuffer()
      ..writeln('# Gerado pelo Oracle AI Setup')
      ..writeln('ORACLE_DB_HOST=$dbHost')
      ..writeln('ORACLE_DB_PORT=$dbPort')
      ..writeln('ORACLE_DB_USER=$dbUser')
      ..writeln('ORACLE_DB_PASSWORD=$dbPassword')
      ..writeln('ORACLE_DB_NAME=$dbName')
      ..writeln('ORACLE_DB_AUTO_CREATE=true')
      ..writeln()
      ..writeln('ORACLE_EMBEDDING_PROVIDER=$embedderProvider');
    if (embedderApiKey.trim().isNotEmpty) {
      final keyVar = switch (embedderProvider) {
        'gemini' => 'GEMINI_API_KEY',
        'openai' => 'OPENAI_API_KEY',
        'voyage' => 'VOYAGE_API_KEY',
        _ => null,
      };
      if (keyVar != null) b.writeln('$keyVar=${embedderApiKey.trim()}');
    }
    b
      ..writeln()
      ..writeln('ORACLE_HTTP_HOST=127.0.0.1')
      ..writeln('ORACLE_HTTP_PORT=49500');
    if (hookToken.isNotEmpty) b.writeln('ORACLE_HOOK_TOKEN=$hookToken');
    b
      ..writeln('ORACLE_METRICS_ENABLED=true')
      ..writeln('ORACLE_MAINTENANCE_INTERVAL_MINUTES=30');
    return b.toString();
  }

  /// Writes the .env, creates/migrates the database and (optionally) restores
  /// a seed found next to the config. Uses the exact same boot path the
  /// server runs, so a wizard success == a working installation.
  Future<void> apply({bool restoreSeed = false}) async {
    busy = true;
    error = null;
    notifyListeners();
    Database? database;
    try {
      final envFile = File(envTargetPath);
      await envFile.parent.create(recursive: true);
      if (envFile.existsSync()) {
        final backup = '${envFile.path}.bak';
        await envFile.copy(backup);
        _log('.env existente preservado em $backup');
      }
      await envFile.writeAsString(buildEnv(), flush: true);
      _log('.env gravado em ${envFile.path}');

      _log('Criando/migrando o banco…');
      final env = loadEnv(path: envFile.path);
      database = await Bootstrap.fromEnv(env).start(ensureDatabase: true);
      _log('Migrations aplicadas.');

      if (restoreSeed) {
        final seed = File('${envFile.parent.path}${Platform.pathSeparator}backups'
            '${Platform.pathSeparator}oracle_seed.sql');
        if (seed.existsSync()) {
          final report = await DbBackupService(database).restore(seed.path);
          _log(report.restored
              ? 'Seed restaurado: ${report.rows} linhas.'
              : 'Seed não restaurado (${report.reason}).');
        } else {
          _log('Nenhum seed em backups/oracle_seed.sql — pulado.');
        }
      }
      installed = true;
      _log('Instalação concluída.');
    } catch (e) {
      error = e is SystemFailure ? e.errorMessage : '$e';
      _log('FALHA: $error');
    } finally {
      await database?.dispose();
      busy = false;
      notifyListeners();
    }
  }

  // ── agent wiring ──

  String get mcpSnippet {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final devBin = File('${File(envTargetPath).parent.path}'
        '${Platform.pathSeparator}build${Platform.pathSeparator}oracle_ai.exe');
    final bin = devBin.existsSync()
        ? devBin.path
        : '$exeDir${Platform.pathSeparator}oracle_ai.exe';
    return mcpJson(command: bin);
  }

  String get hooksSnippet =>
      hooksJson(host: '127.0.0.1', port: 49500, token: hookToken.isEmpty ? null : hookToken);
}
