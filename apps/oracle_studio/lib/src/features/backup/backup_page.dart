import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:oracle_server/oracle_server.dart';

import '../../core/brand.dart';
import '../../core/daemon_host.dart';
import '../../core/fmt.dart';
import '../../core/l10n.dart';
import '../../core/oracle_connection.dart';
import '../../core/settings_store.dart';

/// Backup: informative, with a user-chosen folder (default: Documents ›
/// Oracle AI › backups) shared with the scheduler in Settings.
class BackupPage extends StatefulWidget {
  final OracleConnection connection;
  final DaemonHost daemon;
  const BackupPage({super.key, required this.connection, required this.daemon});

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  bool _running = false;
  DbBackupReport? _lastReport;
  String? _error;

  String get _dir => widget.daemon.settings.backupDir;
  String get _seedPath => '$_dir${Platform.pathSeparator}oracle_seed.sql';

  Future<void> _backupNow() async {
    setState(() {
      _running = true;
      _error = null;
    });
    try {
      final report =
          await DbBackupService(widget.connection.database!).backup(_seedPath);
      setState(() => _lastReport = report);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      setState(() => _running = false);
    }
  }

  Future<void> _pickDir() async {
    final dir = await getDirectoryPath();
    if (dir == null) return;
    widget.daemon.settings.backupDir = dir;
    await widget.daemon.applySettings();
    setState(() {});
  }

  Future<void> _openFolder() async {
    await Directory(_dir).create(recursive: true);
    await Process.run('explorer', [_dir.replaceAll('/', r'\')]);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      children: [
        BrandHeader(l10n.t('bk.title'), subtitle: l10n.t('bk.subtitle')),
        const SizedBox(height: 20),

        SectionCard(
          title: l10n.t('bk.what'),
          description: l10n.t('bk.whatDesc'),
          children: [
            SettingRow(
              label: l10n.t('bk.folder'),
              description: l10n.t('bk.folderDesc'),
              stacked: true,
              control: Row(children: [
                Expanded(
                  child: Text(_dir,
                      style: const TextStyle(fontSize: 13, color: OracleBrand.gray400),
                      overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 8),
                OutlinedButton(onPressed: _pickDir, child: Text(l10n.t('bk.change'))),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () async {
                    widget.daemon.settings.backupDir = defaultBackupDir();
                    await widget.daemon.applySettings();
                    setState(() {});
                  },
                  child: Text(l10n.t('bk.reset')),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: l10n.t('bk.openFolder'),
                  onPressed: _openFolder,
                  icon: const Icon(Icons.folder_open, size: 18),
                ),
              ]),
            ),
            SettingRow(
              label: l10n.t('bk.run'),
              description: l10n.t('bk.explain'),
              control: FilledButton.icon(
                onPressed: _running ? null : _backupNow,
                icon: _running
                    ? const SizedBox(
                        width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save, size: 16),
                label: Text(_running ? l10n.t('bk.running') : l10n.t('bk.run')),
              ),
            ),
          ],
        ),

        if (_error != null) ...[
          const SizedBox(height: 12),
          Text('${l10n.t('common.failure')}: $_error',
              style: const TextStyle(color: OracleBrand.error)),
        ],
        if (_lastReport != null) ...[
          const SizedBox(height: 16),
          SectionCard(
            title: l10n.t('bk.done'),
            description:
                '${_lastReport!.rows} ${l10n.t('bk.rows')} · ${fmtBytes(_lastReport!.bytes)}',
            action: const StatusBadge('OK'),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_lastReport!.path, style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final e in _lastReport!.perTable.entries)
                          Chip(
                            label: Text('${e.key}: ${e.value}'),
                            visualDensity: VisualDensity.compact,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        Text(l10n.t('bk.scheduleNote'), style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
