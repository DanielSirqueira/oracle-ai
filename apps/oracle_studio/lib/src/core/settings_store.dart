import 'dart:convert';
import 'dart:io';

/// Default backup target: the user's Documents folder, in an Oracle AI dir —
/// visible, familiar, and survives repo moves.
String defaultBackupDir() {
  final home =
      Platform.environment['USERPROFILE'] ??
      Platform.environment['HOME'] ??
      '.';
  return '$home${Platform.pathSeparator}Documents${Platform.pathSeparator}Oracle AI'
      '${Platform.pathSeparator}backups';
}

/// Studio settings, persisted as a small JSON in the user's app-data folder
/// (%APPDATA%/OracleAI/studio_settings.json) — independent of the repo .env,
/// which stays the backend's configuration source.
class SettingsStore {
  bool hostHooks;

  /// Whether the Studio hosts the Flow Runner (Loop Engineering) — it claims
  /// queued flow runs and drives them (launching coding agents, git worktrees,
  /// verifiers). Opt-in (off by default) because it actively runs processes.
  bool hostFlowWorker;

  /// How many flow runs the hosted worker drives AT THE SAME TIME (1..8). Each
  /// lane claims its own run; more lanes = more agents running concurrently.
  int flowParallelRuns;
  bool backupEnabled;
  int backupEveryHours;
  int backupKeep;
  String language;
  String backupDir;

  SettingsStore({
    this.hostHooks = true,
    this.hostFlowWorker = false,
    this.flowParallelRuns = 2,
    this.backupEnabled = false,
    this.backupEveryHours = 24,
    this.backupKeep = 7,
    this.language = 'pt',
    String? backupDir,
  }) : backupDir = backupDir ?? defaultBackupDir();

  static String _path() {
    final base =
        Platform.environment['APPDATA'] ??
        Platform.environment['HOME'] ??
        Directory.systemTemp.path;
    return '$base${Platform.pathSeparator}OracleAI${Platform.pathSeparator}studio_settings.json';
  }

  static SettingsStore load() {
    try {
      final file = File(_path());
      if (!file.existsSync()) return SettingsStore();
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      return SettingsStore(
        hostHooks: json['hostHooks'] as bool? ?? true,
        hostFlowWorker: json['hostFlowWorker'] as bool? ?? false,
        flowParallelRuns: json['flowParallelRuns'] as int? ?? 2,
        backupEnabled: json['backupEnabled'] as bool? ?? false,
        backupEveryHours: json['backupEveryHours'] as int? ?? 24,
        backupKeep: json['backupKeep'] as int? ?? 7,
        language: json['language'] as String? ?? 'pt',
        backupDir: json['backupDir'] as String?,
      );
    } catch (_) {
      return SettingsStore(); // corrupt settings never brick the app
    }
  }

  void save() {
    final file = File(_path());
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'hostHooks': hostHooks,
        'hostFlowWorker': hostFlowWorker,
        'flowParallelRuns': flowParallelRuns,
        'backupEnabled': backupEnabled,
        'backupEveryHours': backupEveryHours,
        'backupKeep': backupKeep,
        'language': language,
        'backupDir': backupDir,
      }),
    );
  }
}
