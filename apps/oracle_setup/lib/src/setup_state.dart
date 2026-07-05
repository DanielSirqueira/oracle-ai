import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:oracle_core/oracle_core.dart';
import 'package:oracle_server/oracle_server.dart';

import 'core/l10n.dart';

enum DbMode { existing, docker, portable }

/// The wizard's brain: holds every choice and performs the installation using
/// the same engine code the server/Studio use (PgProvisioner, Bootstrap,
/// DbBackupService) — the wizard is only a UI over proven pieces.
class SetupState extends ChangeNotifier {
  // ── database ──
  // "Automatic" (bundled portable PG) is the default: zero configuration.
  DbMode dbMode = DbMode.portable;
  String dbHost = 'localhost';
  int dbPort = 5432;
  String dbUser = 'postgres';
  String dbPassword = 'postgres';
  String dbName = 'oracle_db';

  bool? existingOk; // null = not probed yet
  bool? dockerOk;
  bool portableReady = false;
  bool dockerReady = false;

  // ── embedder ──
  String embedderProvider = 'local';
  String embedderApiKey = '';
  bool embedTested = false;
  String? embedError;
  int? embedDims;

  // ── backup restore ──
  String? backupFile;
  bool? backupValid;

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

  /// Program install root, following the OS convention for per-user apps
  /// (no admin needed): %LOCALAPPDATA%\Programs\Oracle AI on Windows — the
  /// same pattern VS Code and Claude Desktop use. Binaries + .env live here.
  String get installRoot {
    final sep = Platform.pathSeparator;
    final base = Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path;
    return '$base${sep}Programs${sep}Oracle AI';
  }

  /// Configuration lives WITH the installed program.
  String get envTargetPath => '$installRoot${Platform.pathSeparator}.env';

  /// The MCP/CLI binary's installed location — what agents point at.
  String get installedCli => '$installRoot${Platform.pathSeparator}oracle_ai.exe';

  /// The installed Studio executable.
  String get installedStudio =>
      '$installRoot${Platform.pathSeparator}studio${Platform.pathSeparator}oracle_studio.exe';

  /// Database/data area (cluster, downloads) — app DATA, not program files.
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

  /// Validates the embedding provider FOR REAL: builds the embedder exactly as
  /// the server will and embeds a probe text. A wrong/expired API key fails
  /// here, in the wizard — not silently after install.
  Future<void> testEmbedding() async {
    busy = true;
    embedError = null;
    embedTested = false;
    notifyListeners();
    try {
      final embedder = createEmbedder(EmbeddingConfig.fromEnv({
        'ORACLE_EMBEDDING_PROVIDER': embedderProvider,
        'GEMINI_API_KEY': embedderApiKey.trim(),
        'OPENAI_API_KEY': embedderApiKey.trim(),
        'VOYAGE_API_KEY': embedderApiKey.trim(),
      }));
      final vector = await embedder
          .embed('hello world')
          .timeout(const Duration(seconds: 25));
      if (vector.isEmpty) throw Exception('empty vector');
      embedDims = vector.length;
      embedTested = true;
      _log('${l10n.t('log.embedOk')} (${embedder.model}, $embedDims dims)');
    } catch (e) {
      embedError = '$e';
      _log('${l10n.t('log.embedFail')}: $e');
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// Picks + validates a backup seed: must exist, be non-empty and look like
  /// an Oracle seed (header or INSERT statements) before restore is allowed.
  Future<void> validateBackupFile(String path) async {
    backupFile = path;
    try {
      final file = File(path);
      if (!file.existsSync() || file.lengthSync() == 0) {
        backupValid = false;
      } else {
        final raf = file.openSync();
        final head = String.fromCharCodes(raf.readSync(4096));
        raf.closeSync();
        backupValid = head.contains('Oracle AI') || head.contains('INSERT INTO');
      }
    } catch (_) {
      backupValid = false;
    }
    _log(backupValid == true
        ? '${l10n.t('log.seedValid')}: $path'
        : '${l10n.t('log.seedInvalid')}: $path');
    notifyListeners();
  }

  /// Opens the installed Studio (final wizard step).
  Future<void> launchInstalled() async {
    await Process.start(installedStudio, const [],
        workingDirectory: installRoot, mode: ProcessStartMode.detached);
  }

  /// Version stamped into the Add/Remove Programs entry.
  static const installVersion = '1.4.0';
  static const _publisher = 'Daniel Sirqueira';

  /// Escapes a value for a PowerShell single-quoted string.
  String _psEsc(String s) => s.replaceAll("'", "''");

  /// Registers the app with Windows like a proper installer: a Start Menu and
  /// a Desktop shortcut (per-user, no admin) plus an "Oracle AI" entry under
  /// Settings ▸ Apps / Add-Remove Programs, with a working uninstaller.
  ///
  /// Done via PowerShell's `WScript.Shell` (the standard, admin-free way to
  /// author `.lnk` files) and `HKCU` registry writes. On non-Windows it is a
  /// no-op. The uninstaller removes the program and its shortcuts but **keeps**
  /// the database/memories under [installBase] — a memory bank must not silently
  /// erase what it exists to protect.
  Future<void> _registerWithWindows() async {
    if (!Platform.isWindows) return;
    final sep = Platform.pathSeparator;
    await Directory(installBase).create(recursive: true);
    final uninstallPs1 = '$installBase${sep}uninstall.ps1';
    final registerPs1 = '$installBase${sep}_register.ps1';
    await File(uninstallPs1).writeAsString(_uninstallScript(), flush: true);
    await File(registerPs1).writeAsString(_registerScript(uninstallPs1), flush: true);
    try {
      final r = await Process.run('powershell', [
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden',
        '-File', registerPs1,
      ]);
      if (r.exitCode == 0) {
        _log('  ✓ ${l10n.t('log.shortcuts')}');
      } else {
        _log('  ⚠ ${l10n.t('log.shortcutsFail')}: ${'${r.stderr}'.trim()}');
      }
    } catch (e) {
      _log('  ⚠ ${l10n.t('log.shortcutsFail')}: $e');
    } finally {
      try {
        await File(registerPs1).delete();
      } catch (_) {/* best effort */}
    }
  }

  /// PowerShell that creates the shortcuts and the Add/Remove Programs entry.
  /// Folder paths are resolved at runtime with `GetFolderPath` so a
  /// OneDrive-redirected Desktop/Start Menu still lands in the right place.
  String _registerScript(String uninstallPs1) => r'''
$ErrorActionPreference = 'Stop'
$ws = New-Object -ComObject WScript.Shell
$target = '@@STUDIO@@'
$workdir = '@@ROOT@@'
foreach ($dir in @([Environment]::GetFolderPath('Programs'), [Environment]::GetFolderPath('Desktop'))) {
  $lnk = Join-Path $dir 'Oracle AI.lnk'
  $s = $ws.CreateShortcut($lnk)
  $s.TargetPath = $target
  $s.WorkingDirectory = $workdir
  $s.IconLocation = '@@STUDIO@@,0'
  $s.Description = 'Oracle AI - long-term memory for AI agents'
  $s.Save()
}
$key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\OracleAI'
New-Item -Path $key -Force | Out-Null
Set-ItemProperty -Path $key -Name DisplayName -Value 'Oracle AI'
Set-ItemProperty -Path $key -Name DisplayVersion -Value '@@VER@@'
Set-ItemProperty -Path $key -Name Publisher -Value '@@PUB@@'
Set-ItemProperty -Path $key -Name InstallLocation -Value '@@ROOT@@'
Set-ItemProperty -Path $key -Name DisplayIcon -Value '@@STUDIO@@'
Set-ItemProperty -Path $key -Name NoModify -Value 1 -Type DWord
Set-ItemProperty -Path $key -Name NoRepair -Value 1 -Type DWord
Set-ItemProperty -Path $key -Name UninstallString -Value 'powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "@@UNINST@@"'
'''
      .replaceAll('@@STUDIO@@', _psEsc(installedStudio))
      .replaceAll('@@ROOT@@', _psEsc(installRoot))
      .replaceAll('@@VER@@', installVersion)
      .replaceAll('@@PUB@@', _psEsc(_publisher))
      .replaceAll('@@UNINST@@', _psEsc(uninstallPs1));

  /// The uninstaller: drops the shortcuts, the registry entry and the program
  /// files. It deliberately leaves the data dir (database + memories) intact.
  String _uninstallScript() => r'''
$ErrorActionPreference = 'SilentlyContinue'
Remove-Item (Join-Path ([Environment]::GetFolderPath('Programs')) 'Oracle AI.lnk') -Force
Remove-Item (Join-Path ([Environment]::GetFolderPath('Desktop')) 'Oracle AI.lnk') -Force
Remove-Item 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\OracleAI' -Recurse -Force
Remove-Item -Recurse -Force '@@ROOT@@'
'''
      .replaceAll('@@ROOT@@', _psEsc(installRoot));

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
      _log('${l10n.t('log.payload')}: $fileName');
      return bundled.path;
    }
    final dest = File('$installBase${Platform.pathSeparator}downloads'
        '${Platform.pathSeparator}$fileName');
    // Only a COMPLETED download carries the final name (partials live in
    // .part and are discarded) — an interrupted run can never poison the cache.
    if (dest.existsSync() && dest.lengthSync() > 0) {
      _log('${l10n.t('log.cached')}: $fileName');
      return dest.path;
    }
    await dest.parent.create(recursive: true);
    final part = File('${dest.path}.part');
    if (part.existsSync()) await part.delete();
    _log('${l10n.t('log.downloading')} $fileName…');
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
      final sink = part.openWrite();
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
      if (total > 0 && received != total) {
        throw PgProvisionFailure(
            'download $fileName incompleto ($received de $total bytes)');
      }
      await part.rename(dest.path);
      _log('${l10n.t('log.downloaded')}: $fileName '
          '(${(received / (1024 * 1024)).toStringAsFixed(0)} MB)');
      return dest.path;
    } finally {
      client.close();
    }
  }

  /// The bundled instance's credentials, persisted after a successful init so
  /// EVERY later run (reinstall, re-run of the wizard) reuses the same
  /// password — adopting an already-running cluster only works when we still
  /// know its password.
  File get _credentialsFile =>
      File('$installBase${Platform.pathSeparator}pg-credentials.json');

  String _loadOrCreatePassword() {
    try {
      if (_credentialsFile.existsSync()) {
        final creds =
            jsonDecode(_credentialsFile.readAsStringSync()) as Map<String, dynamic>;
        final saved = creds['password'] as String?;
        if (saved != null && saved.isNotEmpty) {
          _log(l10n.t('log.credsReused'));
          return SecretProtector.unprotect(saved);
        }
      }
    } catch (_) {/* corrupt file → new password */}
    final rnd = Random.secure();
    return List.generate(16, (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  Future<void> _saveCredentials(String password, int port) async {
    await _credentialsFile.parent.create(recursive: true);
    await _credentialsFile.writeAsString(const JsonEncoder.withIndent('  ').convert({
      'user': 'postgres',
      // DPAPI-encrypted at rest; _loadOrCreatePassword decrypts on read.
      'password': SecretProtector.protect(password),
      'port': port,
    }), flush: true);
    _log(l10n.t('log.credsSaved'));
  }

  Future<void> provisionPortable() async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      final pgZip = await _ensureArtifact(_pgUrl, 'postgresql-17.6-1-windows-x64-binaries.zip');
      final vecZip = await _ensureArtifact(_pgvectorUrl, 'vector.v0.8.3-pg17.zip');
      final sep = Platform.pathSeparator;
      const provisioner = PgProvisioner();
      final installDir = '$installBase${sep}pg';
      final dataDir = '$installBase${sep}pgdata';

      var password = _loadOrCreatePassword();
      PgProvisionResult result;
      try {
        result = await provisioner.provisionPortable(
          installDir: installDir,
          dataDir: dataDir,
          pgZip: pgZip,
          pgvectorZip: vecZip,
          password: password,
          onStep: _log,
        );
      } on PgProvisionFailure catch (e) {
        // Self-heal: an adopted cluster that refuses OUR credentials is
        // unusable by anyone (lost password from an interrupted install) —
        // stop it, wipe the data dir and rebuild once from scratch.
        if (!e.message.contains('did not answer')) rethrow;
        _log(l10n.t('log.selfHeal'));
        await provisioner.stop(
            binDir: '$installDir${sep}pgsql${sep}bin', dataDir: dataDir);
        final stale = Directory(dataDir);
        if (stale.existsSync()) await stale.delete(recursive: true);
        final rnd = Random.secure();
        password = List.generate(
            16, (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
        result = await provisioner.provisionPortable(
          installDir: installDir,
          dataDir: dataDir,
          pgZip: pgZip,
          pgvectorZip: vecZip,
          password: password,
          onStep: _log,
        );
      }
      await _saveCredentials(password, result.port);
      // Explicit IPv4: the bundled server listens on 127.0.0.1 only, and
      // 'localhost' resolves to ::1 first on Windows.
      dbHost = '127.0.0.1';
      dbPort = result.port;
      dbUser = 'postgres';
      dbPassword = password;
      portableReady = true;
      _log('${l10n.t('log.dbReady')} localhost:${result.port}.');
    } catch (e) {
      error = '$e';
      _log('${l10n.t('log.fail')}: $e');
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// One-click Docker path: writes a self-contained compose file (pgvector
  /// image, loopback bind, named volume, generated password), runs
  /// `docker compose up -d` and waits until the database answers.
  Future<void> provisionDocker() async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      final rnd = Random.secure();
      final password =
          List.generate(16, (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
      // Off the beaten path (like the bundled instance) so the container never
      // conflicts with other local PostgreSQL installs.
      final port = await PgProvisioner.findFreePort(start: 54330);
      final sep = Platform.pathSeparator;
      final composeFile = File('$installBase${sep}docker$sep' 'docker-compose.yml');
      await composeFile.parent.create(recursive: true);
      await composeFile.writeAsString('''
name: oracle_ai
services:
  db:
    image: pgvector/pgvector:pg17
    container_name: oracle-ai-db
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: $password
      POSTGRES_DB: oracle_db
    ports:
      - "127.0.0.1:$port:5432"
    volumes:
      - oracle_ai_pgdata:/var/lib/postgresql/data
    restart: unless-stopped
volumes:
  oracle_ai_pgdata:
''', flush: true);
      _log('docker compose up -d …');
      final result = await Process.run(
          'docker', ['compose', '-f', composeFile.path, 'up', '-d'],
          runInShell: true);
      if (result.exitCode != 0) {
        throw Exception('docker compose: ${result.stderr}');
      }
      // Wait for the server to answer (image pull + init can take a while).
      final config = DatabaseConfig(
          host: '127.0.0.1', port: port, user: 'postgres', password: password, database: 'postgres');
      var up = false;
      for (var i = 0; i < 60; i++) {
        if (await PgProvisioner.canConnect(config)) {
          up = true;
          break;
        }
        await Future<void>.delayed(const Duration(seconds: 2));
      }
      if (!up) throw Exception('container did not answer at 127.0.0.1:$port');
      dbHost = '127.0.0.1';
      dbPort = port;
      dbUser = 'postgres';
      dbPassword = password;
      dockerReady = true;
      _log('${l10n.t('log.dbReady')} localhost:$port (Docker).');
    } catch (e) {
      error = '$e';
      _log('${l10n.t('log.fail')}: $e');
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
      // Secrets at rest are DPAPI-encrypted (enc:v1:…); loadEnv decrypts them
      // transparently for the CLI/MCP and for our own migrate step below.
      ..writeln('ORACLE_DB_PASSWORD=${SecretProtector.protect(dbPassword)}')
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
      if (keyVar != null) {
        b.writeln('$keyVar=${SecretProtector.protect(embedderApiKey.trim())}');
      }
    }
    b
      ..writeln()
      ..writeln('ORACLE_HTTP_HOST=127.0.0.1')
      ..writeln('ORACLE_HTTP_PORT=49500');
    if (hookToken.isNotEmpty) {
      b.writeln('ORACLE_HOOK_TOKEN=${SecretProtector.protect(hookToken)}');
    }
    b
      ..writeln('ORACLE_METRICS_ENABLED=true')
      ..writeln('ORACLE_MAINTENANCE_INTERVAL_MINUTES=30');
    return b.toString();
  }

  /// Copies a directory tree (the Studio payload) into the install root.
  Future<int> _copyTree(Directory from, Directory to) async {
    var copied = 0;
    await to.create(recursive: true);
    await for (final entity in from.list(recursive: true)) {
      final rel = entity.path.substring(from.path.length + 1);
      final target = '${to.path}${Platform.pathSeparator}$rel';
      if (entity is Directory) {
        await Directory(target).create(recursive: true);
      } else if (entity is File) {
        await entity.copy(target);
        copied++;
      }
    }
    return copied;
  }

  /// The real installation: program files copied to the OS-recommended
  /// per-user location, .env written next to them, database migrated, seed
  /// restored (when picked + valid) and EVERYTHING verified before declaring
  /// success.
  Future<void> apply() async {
    busy = true;
    error = null;
    notifyListeners();
    Database? database;
    try {
      final sep = Platform.pathSeparator;
      await Directory(installRoot).create(recursive: true);

      // 1) Program payload → %LOCALAPPDATA%\Programs\Oracle AI.
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final appPayload = Directory('$exeDir${sep}app');
      if (appPayload.existsSync()) {
        _log('${l10n.t('log.copying')} $installRoot');
        final cli = File('${appPayload.path}${sep}oracle_ai.exe');
        if (cli.existsSync()) await cli.copy(installedCli);
        final studioSrc = Directory('${appPayload.path}${sep}studio');
        if (studioSrc.existsSync()) {
          final n = await _copyTree(studioSrc, Directory('$installRoot${sep}studio'));
          _log('${l10n.t('log.copied')} ($n files)');
        }
      } else {
        _log(l10n.t('log.noAppPayload'));
      }

      // 2) Configuration lives with the program.
      final envFile = File(envTargetPath);
      if (envFile.existsSync()) {
        await envFile.copy('${envFile.path}.bak');
        _log('${l10n.t('log.envKept')} ${envFile.path}.bak');
      }
      await envFile.writeAsString(buildEnv(), flush: true);
      _log('${l10n.t('log.envWritten')} ${envFile.path}');

      // 3) Create + migrate the database.
      _log(l10n.t('log.migrating'));
      final env = loadEnv(path: envFile.path);
      database = await Bootstrap.fromEnv(env).start(ensureDatabase: true);
      _log(l10n.t('log.migrated'));

      // 4) Optional validated backup restore.
      if (backupFile != null && backupValid == true) {
        final report = await DbBackupService(database).restore(backupFile!);
        _log(report.restored
            ? '${l10n.t('log.seedRestored')}: ${report.rows} ${l10n.t('log.rows')}.'
            : '${l10n.t('log.seedSkipped')} (${report.reason}).');
      }

      // 5) OS integration: Start Menu + Desktop shortcuts and an
      //    Add/Remove Programs entry (with an uninstaller) — what makes this a
      //    real installer, not just a file copy.
      await _registerWithWindows();

      // 6) Final validation — nothing is "installed" until it all checks out.
      _log(l10n.t('log.validating'));
      final probe = await database.select(const SqlStatement(
          "SELECT count(*) AS n FROM information_schema.tables "
          "WHERE table_name IN ('memories','skills','rules')", {}));
      final tables = probe.rows.first['n']?.toInt() ?? 0;
      if (tables < 3) throw Exception('schema incompleto ($tables/3 tabelas)');
      _log('  ✓ ${l10n.t('log.vSchema')}');
      if (File(installedCli).existsSync()) {
        _log('  ✓ MCP: $installedCli');
      } else {
        _log('  ⚠ ${l10n.t('log.vNoCli')}');
      }
      if (File(installedStudio).existsSync()) {
        _log('  ✓ Studio: $installedStudio');
      } else {
        _log('  ⚠ ${l10n.t('log.vNoStudio')}');
      }
      installed = true;
      _log(l10n.t('log.done'));
    } catch (e) {
      error = e is SystemFailure ? e.errorMessage : '$e';
      _log('${l10n.t('log.fail')}: $error');
    } finally {
      await database?.dispose();
      busy = false;
      notifyListeners();
    }
  }

  // ── agent wiring ──

  /// Agents point at the INSTALLED binary — the MCP lives with the program.
  String get mcpSnippet => mcpJson(command: installedCli);

  /// Detailed instruction block to paste into the agent's CLAUDE.md/AGENTS.md.
  String get agentPrompt => agentProtocol().trim();

  String get hooksSnippet =>
      hooksJson(host: '127.0.0.1', port: 49500, token: hookToken.isEmpty ? null : hookToken);
}
