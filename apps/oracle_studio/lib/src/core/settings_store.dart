import 'dart:convert';
import 'dart:io';

/// Studio settings, persisted as a small JSON in the user's app-data folder
/// (%APPDATA%/OracleAI/studio_settings.json) — independent of the repo .env,
/// which stays the backend's configuration source.
class SettingsStore {
  bool hostHooks;
  bool backupEnabled;
  int backupEveryHours;
  int backupKeep;

  SettingsStore({
    this.hostHooks = true,
    this.backupEnabled = false,
    this.backupEveryHours = 24,
    this.backupKeep = 7,
  });

  static String _path() {
    final base = Platform.environment['APPDATA'] ??
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
        backupEnabled: json['backupEnabled'] as bool? ?? false,
        backupEveryHours: json['backupEveryHours'] as int? ?? 24,
        backupKeep: json['backupKeep'] as int? ?? 7,
      );
    } catch (_) {
      return SettingsStore(); // corrupt settings never brick the app
    }
  }

  void save() {
    final file = File(_path());
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert({
      'hostHooks': hostHooks,
      'backupEnabled': backupEnabled,
      'backupEveryHours': backupEveryHours,
      'backupKeep': backupKeep,
    }));
  }
}
