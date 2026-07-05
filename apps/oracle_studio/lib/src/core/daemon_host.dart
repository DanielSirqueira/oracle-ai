import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:oracle_server/oracle_server.dart';

import 'oracle_connection.dart';
import 'settings_store.dart';

/// The Studio's background side: it can HOST the hook receiver + maintenance
/// scheduler (replacing the console `serve-hooks` daemon) and run scheduled
/// backups — all while the window sits hidden in the tray.
class DaemonHost extends ChangeNotifier {
  final OracleConnection connection;
  final SettingsStore settings;

  HooksServer? _hooks;
  MaintenanceScheduler? _scheduler;
  Timer? _backupTimer;

  bool get hooksRunning => _hooks != null;
  String hooksStatus = 'desligado';

  DateTime? lastBackupAt;
  String? lastBackupInfo;
  String? lastBackupError;
  bool backingUp = false;

  DaemonHost({required this.connection, required this.settings}) {
    connection.addListener(_onConnectionChanged);
    _onConnectionChanged();
  }

  void _onConnectionChanged() {
    if (connection.status == OracleConnectionStatus.connected) {
      applySettings();
    }
  }

  /// Starts/stops the hosted pieces according to [settings]. Safe to re-call.
  Future<void> applySettings() async {
    settings.save();
    await _applyHooks();
    _applyBackupTimer();
    notifyListeners();
  }

  Future<void> _applyHooks() async {
    if (!settings.hostHooks || connection.status != OracleConnectionStatus.connected) {
      await _hooks?.stop();
      _hooks = null;
      _scheduler?.stop();
      _scheduler = null;
      hooksStatus = 'desligado';
      return;
    }
    if (_hooks != null) return; // already up

    final env = connection.env;
    final server = HooksServer(
      host: env['ORACLE_HTTP_HOST'] ?? '127.0.0.1',
      port: int.tryParse(env['ORACLE_HTTP_PORT'] ?? '') ?? 49500,
      hookToken: env['ORACLE_HOOK_TOKEN'],
      metricsEnabled: env['ORACLE_METRICS_ENABLED'] == null
          ? null
          : env['ORACLE_METRICS_ENABLED']!.toLowerCase() == 'true',
      metricsLabel: env['ORACLE_METRICS_LABEL'],
    );
    try {
      await server.start();
      _hooks = server;
      hooksStatus = 'ativo em ${server.host}:${server.port}';
      // The maintenance scheduler belongs to whoever owns the hooks (one place,
      // no per-agent duplication) — same rule the console daemon followed.
      final intervalMin =
          int.tryParse(env['ORACLE_MAINTENANCE_INTERVAL_MINUTES'] ?? '') ?? 0;
      if (intervalMin > 0) {
        _scheduler = MaintenanceScheduler(interval: Duration(minutes: intervalMin))..start();
      }
    } on SocketException catch (e) {
      hooksStatus =
          'porta ocupada (${e.osError?.message ?? e.message}) — outro daemon já serve os hooks; '
          'encerre o oracle_ai.exe de console para o Studio assumir';
    }
  }

  void _applyBackupTimer() {
    _backupTimer?.cancel();
    _backupTimer = null;
    if (!settings.backupEnabled) return;
    final interval = Duration(hours: settings.backupEveryHours);
    _backupTimer = Timer.periodic(interval, (_) => backupNow());
  }

  /// Scheduled/tray backup: a timestamped snapshot in the backups folder, with
  /// retention (keep the newest N). The plain `oracle_seed.sql` (for commits /
  /// docker seed) stays a manual action on the Backup page.
  Future<void> backupNow() async {
    final db = connection.database;
    if (db == null || backingUp) return;
    backingUp = true;
    lastBackupError = null;
    notifyListeners();
    try {
      final dir = settings.backupDir;
      final now = DateTime.now();
      final stamp = '${now.year}-${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}'
          '${now.minute.toString().padLeft(2, '0')}';
      final report =
          await DbBackupService(db).backup('$dir${Platform.pathSeparator}oracle_backup_$stamp.sql');
      lastBackupAt = now;
      lastBackupInfo = '${report.rows} linhas · ${(report.bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
      await _prune(Directory(dir));
    } catch (e) {
      lastBackupError = '$e';
    } finally {
      backingUp = false;
      notifyListeners();
    }
  }

  /// Keeps only the newest [SettingsStore.backupKeep] scheduled snapshots.
  Future<void> _prune(Directory dir) async {
    if (!await dir.exists()) return;
    final snapshots = <File>[];
    await for (final f in dir.list()) {
      if (f is File && f.uri.pathSegments.last.startsWith('oracle_backup_')) {
        snapshots.add(f);
      }
    }
    snapshots.sort((a, b) => b.path.compareTo(a.path)); // stamp in name = sortable
    for (final old in snapshots.skip(settings.backupKeep)) {
      await old.delete();
    }
  }

  Future<void> shutdown() async {
    _backupTimer?.cancel();
    _scheduler?.stop();
    await _hooks?.stop();
  }

  @override
  void dispose() {
    connection.removeListener(_onConnectionChanged);
    super.dispose();
  }
}
