import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:oracle_server/oracle_server.dart' as server;

import '../../core/brand.dart';
import '../../core/daemon_host.dart';
import '../../core/fmt.dart';
import '../../core/l10n.dart';
import '../../core/oracle_connection.dart';
import '../../widgets/editor_dialog.dart';

/// Settings: language, daemon hosting (hooks + maintenance), scheduled
/// backups, agent integration snippets (MCP + hooks) and the .env editor.
class SettingsPage extends StatefulWidget {
  final OracleConnection connection;
  final DaemonHost daemon;
  const SettingsPage({super.key, required this.connection, required this.daemon});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _envController;
  bool _envDirty = false;
  bool _autostart = false;

  @override
  void initState() {
    super.initState();
    final path = widget.connection.envPath;
    final content =
        (path != null && File(path).existsSync()) ? File(path).readAsStringSync() : '';
    _envController = TextEditingController(text: content)
      ..addListener(() => setState(() => _envDirty = true));
    launchAtStartup.isEnabled().then((v) {
      if (mounted) setState(() => _autostart = v);
    });
  }

  Future<void> _setAutostart(bool enable) async {
    if (enable) {
      await launchAtStartup.enable();
    } else {
      await launchAtStartup.disable();
    }
    final actual = await launchAtStartup.isEnabled();
    if (mounted) {
      setState(() => _autostart = actual);
      showSnack(context, actual ? l10n.t('set.autostartOn') : l10n.t('set.autostartOff'));
    }
  }

  @override
  void dispose() {
    _envController.dispose();
    super.dispose();
  }

  Future<void> _saveEnv() async {
    final path = widget.connection.envPath;
    if (path == null) {
      showSnack(context, l10n.t('set.envMissing'));
      return;
    }
    await File(path).writeAsString(_envController.text, flush: true);
    if (!mounted) return;
    setState(() => _envDirty = false);
    showSnack(context, l10n.t('set.envSaved'));
  }

  void _copy(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    showSnack(context, '$label ${l10n.t('set.copied')}');
  }

  @override
  Widget build(BuildContext context) {
    final daemon = widget.daemon;
    final settings = daemon.settings;
    final env = widget.connection.env;
    final binPath = widget.connection.envDir == null
        ? 'oracle_ai.exe'
        : '${widget.connection.envDir}${Platform.pathSeparator}build${Platform.pathSeparator}oracle_ai.exe';
    final mcpSnippet = server.mcpJson(command: binPath);
    final hooksSnippet = server.hooksJson(
      host: env['ORACLE_HTTP_HOST'] ?? '127.0.0.1',
      port: int.tryParse(env['ORACLE_HTTP_PORT'] ?? '') ?? 49500,
      token: env['ORACLE_HOOK_TOKEN'],
    );

    return AnimatedBuilder(
      animation: daemon,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.all(24),
        children: [
          BrandHeader(
            l10n.t('set.title'),
            trailing: Row(children: [
              const Icon(Icons.translate, size: 18),
              const SizedBox(width: 8),
              DropdownButton<String>(
                value: l10n.code,
                underline: const SizedBox.shrink(),
                items: const [
                  DropdownMenuItem(value: 'pt', child: Text('Português')),
                  DropdownMenuItem(value: 'en', child: Text('English')),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  settings.language = v;
                  settings.save();
                  l10n.set(v);
                },
              ),
            ]),
          ),
          const SizedBox(height: 20),

          // ── daemon ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.t('set.daemon'), style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(l10n.t('set.daemonExplain'),
                      style: Theme.of(context).textTheme.bodySmall),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l10n.t('set.hostToggle')),
                    subtitle: Text(daemon.hooksStatus),
                    value: settings.hostHooks,
                    onChanged: (v) {
                      settings.hostHooks = v;
                      daemon.applySettings();
                    },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l10n.t('set.autostart')),
                    subtitle: Text(l10n.t('set.autostartSub')),
                    value: _autostart,
                    onChanged: _setAutostart,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ── scheduled backup ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.t('set.schedTitle'),
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(l10n.t('set.schedExplain'),
                      style: Theme.of(context).textTheme.bodySmall),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l10n.t('set.schedToggle')),
                    value: settings.backupEnabled,
                    onChanged: (v) {
                      settings.backupEnabled = v;
                      daemon.applySettings();
                    },
                  ),
                  Row(children: [
                    Text(l10n.t('set.every')),
                    const SizedBox(width: 12),
                    DropdownButton<int>(
                      value: settings.backupEveryHours,
                      items: [
                        DropdownMenuItem(value: 6, child: Text(l10n.t('set.hours6'))),
                        DropdownMenuItem(value: 12, child: Text(l10n.t('set.hours12'))),
                        DropdownMenuItem(value: 24, child: Text(l10n.t('set.hours24'))),
                        DropdownMenuItem(value: 48, child: Text(l10n.t('set.hours48'))),
                      ],
                      onChanged: (v) {
                        settings.backupEveryHours = v ?? 24;
                        daemon.applySettings();
                      },
                    ),
                    const SizedBox(width: 24),
                    Text(l10n.t('set.keepLast')),
                    const SizedBox(width: 12),
                    DropdownButton<int>(
                      value: settings.backupKeep,
                      items: const [
                        DropdownMenuItem(value: 3, child: Text('3')),
                        DropdownMenuItem(value: 7, child: Text('7')),
                        DropdownMenuItem(value: 14, child: Text('14')),
                        DropdownMenuItem(value: 30, child: Text('30')),
                      ],
                      onChanged: (v) {
                        settings.backupKeep = v ?? 7;
                        daemon.applySettings();
                      },
                    ),
                    const Spacer(),
                    OutlinedButton.icon(
                      onPressed: daemon.backingUp ? null : daemon.backupNow,
                      icon: daemon.backingUp
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.save_outlined),
                      label: Text(
                          daemon.backingUp ? l10n.t('set.runningNow') : l10n.t('set.runNow')),
                    ),
                  ]),
                  if (daemon.lastBackupAt != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '${l10n.t('set.lastBackup')}: ${fmtDateTime(daemon.lastBackupAt)}'
                        ' — ${daemon.lastBackupInfo}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  if (daemon.lastBackupError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text('${l10n.t('common.failure')}: ${daemon.lastBackupError}',
                          style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ── agent integration ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.t('set.agents'), style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  _SnippetBlock(
                    title: l10n.t('set.mcpTitle'),
                    snippet: mcpSnippet,
                    onCopy: () => _copy(mcpSnippet, '.mcp.json'),
                  ),
                  const SizedBox(height: 12),
                  _SnippetBlock(
                    title: l10n.t('set.hooksTitle'),
                    snippet: hooksSnippet,
                    onCopy: () => _copy(hooksSnippet, '"hooks"'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ── .env editor ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text('.env', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(width: 8),
                    Text(widget.connection.envPath ?? l10n.t('set.envNotFound'),
                        style: Theme.of(context).textTheme.bodySmall),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: _envDirty ? _saveEnv : null,
                      icon: const Icon(Icons.save),
                      label: Text(l10n.t('set.envSave')),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _envController,
                    maxLines: 14,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                    decoration: const InputDecoration(border: OutlineInputBorder()),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SnippetBlock extends StatelessWidget {
  final String title;
  final String snippet;
  final VoidCallback onCopy;
  const _SnippetBlock({required this.title, required this.snippet, required this.onCopy});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(child: Text(title, style: Theme.of(context).textTheme.labelLarge)),
          IconButton(
              tooltip: l10n.t('set.copy'),
              onPressed: onCopy,
              icon: const Icon(Icons.copy, size: 18)),
        ]),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: OracleBrand.surfaceHigh,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: OracleBrand.violet.withValues(alpha: 0.2)),
          ),
          child: SelectableText(
            snippet,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),
      ],
    );
  }
}
