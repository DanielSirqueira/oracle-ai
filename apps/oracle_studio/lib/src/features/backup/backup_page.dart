import 'package:flutter/material.dart';
import 'package:oracle_server/oracle_server.dart';

import '../../core/brand.dart';
import '../../core/fmt.dart';
import '../../core/l10n.dart';
import '../../core/oracle_connection.dart';

/// Backup control: run a portable data-seed backup now. Scheduling lives in
/// Settings (the Studio's background daemon runs it).
class BackupPage extends StatefulWidget {
  final OracleConnection connection;
  const BackupPage({super.key, required this.connection});

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  bool _running = false;
  DbBackupReport? _lastReport;
  String? _error;

  String get _defaultPath {
    final dir = widget.connection.envDir;
    return dir == null ? 'backups/oracle_seed.sql' : '$dir/backups/oracle_seed.sql';
  }

  Future<void> _backupNow() async {
    setState(() {
      _running = true;
      _error = null;
    });
    try {
      final report =
          await DbBackupService(widget.connection.database!).backup(_defaultPath);
      setState(() => _lastReport = report);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        BrandHeader(l10n.t('bk.title')),
        const SizedBox(height: 12),
        Text(l10n.t('bk.explain'), style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.description_outlined, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text('${l10n.t('bk.target')}: $_defaultPath')),
                  ],
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _running ? null : _backupNow,
                  icon: _running
                      ? const SizedBox(
                          width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.save),
                  label: Text(_running ? l10n.t('bk.running') : l10n.t('bk.run')),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text('${l10n.t('common.failure')}: $_error',
                      style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
              ],
            ),
          ),
        ),
        if (_lastReport != null) ...[
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.check_circle, color: Color(0xFF4ADE80), size: 18),
                    const SizedBox(width: 8),
                    Text(l10n.t('bk.done'), style: Theme.of(context).textTheme.titleMedium),
                  ]),
                  const SizedBox(height: 8),
                  Text('${_lastReport!.rows} ${l10n.t('bk.rows')} · '
                      '${fmtBytes(_lastReport!.bytes)}'),
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
          ),
        ],
        const SizedBox(height: 16),
        Text(l10n.t('bk.scheduleNote'), style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
