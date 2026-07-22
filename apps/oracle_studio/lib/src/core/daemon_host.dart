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
  Timer? _hooksRetry;

  bool get hooksRunning => _hooks != null;

  /// Hooks hosting state as a CODE ('off' | 'on' | 'reserved' | 'busy') plus a
  /// language-neutral detail (address / OS message) — the UI localizes it.
  String hooksStatus = 'off';
  String hooksStatusDetail = '';

  /// Flow Runner (Loop Engineering) hosting state. [workerStatus] is a CODE
  /// ('off' | 'on' | 'stopping') — the UI localizes it.
  bool workerRunning = false;
  String workerStatus = 'off';
  String workerStatusDetail = '';
  bool _workerStop = false;

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
    _applyFlowWorker();
    notifyListeners();
  }

  /// Starts (or lets stop) the hosted Flow Runner according to [settings]. Up
  /// to [SettingsStore.flowParallelRuns] LANES run concurrently — each lane
  /// claims its own run (`FOR UPDATE SKIP LOCKED` makes double-claims
  /// impossible), so several processes execute at the same time. Lanes observe
  /// the flags and exit on their own; this only tops up missing lanes.
  void _applyFlowWorker() {
    final wantRunning =
        settings.hostFlowWorker &&
        connection.status == OracleConnectionStatus.connected &&
        !_workerStop;
    final desired = wantRunning ? _desiredLanes() : 0;
    while (_lanes < desired) {
      final index = _lanes;
      _lanes++;
      workerRunning = true;
      workerStatus = 'on';
      workerStatusDetail = '';
      unawaited(_flowWorkerLoop(index));
    }
    if (!settings.hostFlowWorker) {
      workerStatus = workerRunning ? 'stopping' : 'off';
    }
  }

  int _lanes = 0;
  int _desiredLanes() => settings.flowParallelRuns.clamp(1, 8);

  /// One claim-and-drive lane: pulls one queued flow run at a time and drives it
  /// to a stopping point (completion / gate), then idles. Exits when hosting is
  /// disabled, the connection drops, the Studio shuts down, or the parallelism
  /// setting was lowered below this lane's index.
  Future<void> _flowWorkerLoop(int index) async {
    bool keepGoing() =>
        settings.hostFlowWorker &&
        connection.status == OracleConnectionStatus.connected &&
        !_workerStop &&
        index < _desiredLanes();

    final worker = FlowWorker(language: settings.language);
    final workerId = 'studio-$pid-${index + 1}';
    while (keepGoing()) {
      var worked = false;
      try {
        worked = await worker.runOnce(workerId);
        if (workerStatusDetail.isNotEmpty) {
          workerStatusDetail = '';
          notifyListeners();
        }
      } catch (error, stackTrace) {
        final message = error.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
        workerStatusDetail = message.length <= 240
            ? message
            : '${message.substring(0, 237)}...';
        debugPrint('Flow Runner polling failed: $error\n$stackTrace');
        notifyListeners();
      }
      if (!keepGoing()) break;
      await Future<void>.delayed(
        worked ? const Duration(milliseconds: 500) : const Duration(seconds: 5),
      );
    }
    _lanes--;
    if (_lanes <= 0) {
      _lanes = 0;
      workerRunning = false;
      workerStatus = 'off';
      workerStatusDetail = '';
    }
    notifyListeners();
  }

  Future<void> _applyHooks() async {
    if (!settings.hostHooks ||
        connection.status != OracleConnectionStatus.connected) {
      _hooksRetry?.cancel();
      _hooksRetry = null;
      await _hooks?.stop();
      _hooks = null;
      _scheduler?.stop();
      _scheduler = null;
      hooksStatus = 'off';
      hooksStatusDetail = '';
      return;
    }
    if (_hooks != null) return; // already up

    final env = connection.env;
    final server = HooksServer(
      host: env['ORACLE_HTTP_HOST'] ?? '127.0.0.1',
      port: int.tryParse(env['ORACLE_HTTP_PORT'] ?? '') ?? 47500,
      hookToken: env['ORACLE_HOOK_TOKEN'],
      metricsEnabled: env['ORACLE_METRICS_ENABLED'] == null
          ? null
          : env['ORACLE_METRICS_ENABLED']!.toLowerCase() == 'true',
      metricsLabel: env['ORACLE_METRICS_LABEL'],
    );
    try {
      await server.start();
      _hooks = server;
      _hooksRetry?.cancel(); // bound — stop retrying
      _hooksRetry = null;
      hooksStatus = 'on';
      hooksStatusDetail = '${server.host}:${server.port}';
      // The maintenance scheduler belongs to whoever owns the hooks (one place,
      // no per-agent duplication) — same rule the console daemon followed.
      final intervalMin =
          int.tryParse(env['ORACLE_MAINTENANCE_INTERVAL_MINUTES'] ?? '') ?? 0;
      if (intervalMin > 0) {
        _scheduler = MaintenanceScheduler(
          interval: Duration(minutes: intervalMin),
        )..start();
      }
    } on SocketException catch (e) {
      // Two distinct failures land here:
      //  • access denied (Win WSAEACCES 10013 / POSIX EACCES 13): the port sits in
      //    a range the OS reserves — on Windows that's the dynamic range (>=49152,
      //    carved up by WinNAT/Hyper-V). Retrying is futile; the user must pick a
      //    port below 49152. Say so plainly instead of "port busy".
      //  • in use: another daemon (Docker/console) holds it — keep retrying so the
      //    Studio AUTOMATICALLY takes over the moment that process stops.
      final code = e.osError?.errorCode;
      final accessDenied = code == 10013 || code == 13;
      hooksStatus = accessDenied ? 'reserved' : 'busy';
      hooksStatusDetail = '${server.port}';
      _scheduleHooksRetry();
    }
  }

  /// While hosting is enabled but the port is busy, re-attempt binding every few
  /// seconds so the Studio self-heals into the hook receiver when the port frees.
  void _scheduleHooksRetry() {
    _hooksRetry ??= Timer.periodic(const Duration(seconds: 10), (_) async {
      if (_hooks != null ||
          !settings.hostHooks ||
          connection.status != OracleConnectionStatus.connected) {
        _hooksRetry?.cancel();
        _hooksRetry = null;
        return;
      }
      await _applyHooks();
      notifyListeners();
    });
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
      final stamp =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}'
          '${now.minute.toString().padLeft(2, '0')}';
      final report = await DbBackupService(
        db,
      ).backup('$dir${Platform.pathSeparator}oracle_backup_$stamp.sql');
      lastBackupAt = now;
      lastBackupInfo =
          '${report.rows} linhas · ${(report.bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
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
    snapshots.sort(
      (a, b) => b.path.compareTo(a.path),
    ); // stamp in name = sortable
    for (final old in snapshots.skip(settings.backupKeep)) {
      await old.delete();
    }
  }

  Future<void> shutdown() async {
    _workerStop = true;
    _backupTimer?.cancel();
    _hooksRetry?.cancel();
    _scheduler?.stop();
    await _hooks?.stop();
  }

  @override
  void dispose() {
    connection.removeListener(_onConnectionChanged);
    super.dispose();
  }
}
