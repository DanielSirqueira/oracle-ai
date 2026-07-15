import 'dart:io';
import 'dart:math';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:oracle_server/oracle_server.dart' as server;

import '../../core/brand.dart';
import '../../core/daemon_host.dart';
import '../../core/env_editor.dart';
import '../../core/fmt.dart';
import '../../core/l10n.dart';
import '../../core/oracle_connection.dart';
import '../../core/settings_store.dart';
import '../../widgets/editor_dialog.dart';
import '../../widgets/markdown_view.dart';

/// Settings, Untitled-UI style: structured sections with label/description
/// rows. The .env is edited through a FORM (merge-saved, comments preserved);
/// the raw editor survives only as an "advanced" expander.
class SettingsPage extends StatefulWidget {
  final OracleConnection connection;
  final DaemonHost daemon;
  const SettingsPage({super.key, required this.connection, required this.daemon});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _autostart = false;

  // .env form controllers, seeded from the live connection env.
  late final _dbHost = TextEditingController(text: _env('ORACLE_DB_HOST', 'localhost'));
  late final _dbPort = TextEditingController(text: _env('ORACLE_DB_PORT', '5432'));
  late final _dbUser = TextEditingController(text: _env('ORACLE_DB_USER', 'postgres'));
  late final _dbPass = TextEditingController(text: _env('ORACLE_DB_PASSWORD', ''));
  late final _dbName = TextEditingController(text: _env('ORACLE_DB_NAME', 'oracle_db'));
  late String _provider = _env('ORACLE_EMBEDDING_PROVIDER', 'local');
  late final _apiKey = TextEditingController(text: _providerKeyValue());
  late final _httpHost = TextEditingController(text: _env('ORACLE_HTTP_HOST', '127.0.0.1'));
  late final _httpPort = TextEditingController(text: _env('ORACLE_HTTP_PORT', '47500'));
  late final _token = TextEditingController(text: _env('ORACLE_HOOK_TOKEN', ''));
  late final _maintMin =
      TextEditingController(text: _env('ORACLE_MAINTENANCE_INTERVAL_MINUTES', '30'));
  late final _metricsLabel = TextEditingController(text: _env('ORACLE_METRICS_LABEL', 'default'));
  late final TextEditingController _rawEnv;
  bool _savingEnv = false;

  String _env(String key, String fallback) => widget.connection.env[key] ?? fallback;

  String _providerKeyVar() => switch (_provider) {
        'gemini' => 'GEMINI_API_KEY',
        'openai' => 'OPENAI_API_KEY',
        'voyage' => 'VOYAGE_API_KEY',
        _ => 'GEMINI_API_KEY',
      };

  String _providerKeyValue() => widget.connection.env[_providerKeyVar()] ?? '';

  @override
  void initState() {
    super.initState();
    final path = widget.connection.envPath;
    _rawEnv = TextEditingController(
        text: (path != null && File(path).existsSync()) ? File(path).readAsStringSync() : '');
    launchAtStartup.isEnabled().then((v) {
      if (mounted) setState(() => _autostart = v);
    });
  }

  @override
  void dispose() {
    for (final c in [
      _dbHost, _dbPort, _dbUser, _dbPass, _dbName, _apiKey,
      _httpHost, _httpPort, _token, _maintMin, _metricsLabel, _rawEnv,
    ]) {
      c.dispose();
    }
    super.dispose();
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

  Future<void> _saveEnvForm() async {
    final path = widget.connection.envPath;
    if (path == null) {
      showSnack(context, l10n.t('set.envMissing'));
      return;
    }
    setState(() => _savingEnv = true);
    try {
      await EnvEditor.apply(path, {
        'ORACLE_DB_HOST': _dbHost.text.trim(),
        'ORACLE_DB_PORT': _dbPort.text.trim(),
        'ORACLE_DB_USER': _dbUser.text.trim(),
        'ORACLE_DB_PASSWORD': _dbPass.text,
        'ORACLE_DB_NAME': _dbName.text.trim(),
        'ORACLE_EMBEDDING_PROVIDER': _provider,
        _providerKeyVar(): _apiKey.text.trim(),
        'ORACLE_HTTP_HOST': _httpHost.text.trim(),
        'ORACLE_HTTP_PORT': _httpPort.text.trim(),
        'ORACLE_HOOK_TOKEN': _token.text.trim(),
        'ORACLE_MAINTENANCE_INTERVAL_MINUTES': _maintMin.text.trim(),
        'ORACLE_METRICS_LABEL': _metricsLabel.text.trim(),
      });
      _rawEnv.text = File(path).readAsStringSync();
      if (mounted) showSnack(context, l10n.t('env.saved'));
    } catch (e) {
      if (mounted) showSnack(context, '${l10n.t('common.failure')}: $e');
    } finally {
      if (mounted) setState(() => _savingEnv = false);
    }
  }

  void _generateToken() {
    final rnd = Random.secure();
    _token.text =
        List.generate(32, (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    setState(() {});
  }

  Future<void> _pickBackupDir() async {
    final dir = await getDirectoryPath();
    if (dir == null) return;
    widget.daemon.settings.backupDir = dir;
    await widget.daemon.applySettings();
    setState(() {});
  }

  void _copy(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    showSnack(context, '$label ${l10n.t('set.copied')}');
  }

  Widget _field(TextEditingController c, {String? hint, bool obscure = false, double width = 260}) {
    return SizedBox(
      width: width,
      child: TextField(
        controller: c,
        obscureText: obscure,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(hintText: hint, isDense: true),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final daemon = widget.daemon;
    final settings = daemon.settings;
    // The CLI binary sits NEXT TO the .env (installer puts oracle_ai.exe and .env
    // together in the program root). No `build\` subfolder — that was the dev-tree
    // layout and produced a path that doesn't exist in an install.
    final binPath = widget.connection.envDir == null
        ? 'oracle_ai.exe'
        : '${widget.connection.envDir}${Platform.pathSeparator}oracle_ai.exe';
    final mcpSnippet = server.mcpJson(command: binPath);
    final hooksSnippet = server.hooksJson(
      host: _httpHost.text.trim(),
      port: int.tryParse(_httpPort.text.trim()) ?? 47500,
      token: _token.text.trim().isEmpty ? null : _token.text.trim(),
    );

    return AnimatedBuilder(
      animation: daemon,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        children: [
          BrandHeader(
            l10n.t('set.title'),
            subtitle: l10n.t('set.subtitle'),
            trailing: Row(children: [
              const Icon(Icons.translate, size: 16, color: OracleBrand.gray400),
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
          SectionCard(
            title: l10n.t('set.daemon'),
            description: l10n.t('set.daemonExplain'),
            action: StatusBadge(
              daemon.hooksRunning
                  ? l10n.t('set.online')
                  : (settings.hostHooks ? l10n.t('set.portBusy') : l10n.t('set.offline')),
              color: daemon.hooksRunning
                  ? OracleBrand.success
                  : (settings.hostHooks ? OracleBrand.warning : OracleBrand.gray500),
            ),
            children: [
              SettingRow(
                label: l10n.t('set.hostToggle'),
                description: daemon.hooksStatus,
                control: Switch(
                  value: settings.hostHooks,
                  onChanged: (v) {
                    settings.hostHooks = v;
                    daemon.applySettings();
                  },
                ),
              ),
              SettingRow(
                label: l10n.t('set.autostart'),
                description: l10n.t('set.autostartSub'),
                control: Switch(value: _autostart, onChanged: _setAutostart),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── scheduled backup ──
          SectionCard(
            title: l10n.t('set.schedTitle'),
            description: l10n.t('set.schedExplain'),
            children: [
              SettingRow(
                label: l10n.t('set.schedToggle'),
                control: Switch(
                  value: settings.backupEnabled,
                  onChanged: (v) {
                    settings.backupEnabled = v;
                    daemon.applySettings();
                  },
                ),
              ),
              SettingRow(
                label: l10n.t('bk.folder'),
                description: l10n.t('bk.folderDesc'),
                stacked: true,
                control: Row(children: [
                  Expanded(
                    child: Text(settings.backupDir,
                        style: const TextStyle(fontSize: 13, color: OracleBrand.gray400),
                        overflow: TextOverflow.ellipsis),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                      onPressed: _pickBackupDir, child: Text(l10n.t('bk.change'))),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () async {
                      settings.backupDir = defaultBackupDir();
                      await daemon.applySettings();
                      setState(() {});
                    },
                    child: Text(l10n.t('bk.reset')),
                  ),
                ]),
              ),
              SettingRow(
                label: '${l10n.t('set.every')} / ${l10n.t('set.keepLast')}',
                control: Row(mainAxisSize: MainAxisSize.min, children: [
                  DropdownButton<int>(
                    value: settings.backupEveryHours,
                    underline: const SizedBox.shrink(),
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
                  const SizedBox(width: 16),
                  DropdownButton<int>(
                    value: settings.backupKeep,
                    underline: const SizedBox.shrink(),
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
                  const SizedBox(width: 16),
                  OutlinedButton.icon(
                    onPressed: daemon.backingUp ? null : daemon.backupNow,
                    icon: daemon.backingUp
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.save_outlined, size: 16),
                    label: Text(
                        daemon.backingUp ? l10n.t('set.runningNow') : l10n.t('set.runNow')),
                  ),
                ]),
              ),
              if (daemon.lastBackupAt != null || daemon.lastBackupError != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: daemon.lastBackupError != null
                      ? Text('${l10n.t('common.failure')}: ${daemon.lastBackupError}',
                          style: const TextStyle(color: OracleBrand.error, fontSize: 13))
                      : Text(
                          '${l10n.t('set.lastBackup')}: ${fmtDateTime(daemon.lastBackupAt)}'
                          ' — ${daemon.lastBackupInfo}',
                          style: Theme.of(context).textTheme.bodySmall),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // ── .env structured form ──
          SectionCard(
            title: l10n.t('env.title'),
            description: l10n.t('env.desc'),
            action: FilledButton.icon(
              onPressed: _savingEnv ? null : _saveEnvForm,
              icon: _savingEnv
                  ? const SizedBox(
                      width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save, size: 16),
              label: Text(l10n.t('env.save')),
            ),
            children: [
              SettingRow(
                label: l10n.t('env.db'),
                description: l10n.t('env.dbDesc'),
                stacked: true,
                control: Wrap(spacing: 12, runSpacing: 12, children: [
                  _labeled(l10n.t('env.host'), _field(_dbHost, width: 220)),
                  _labeled(l10n.t('env.port'), _field(_dbPort, width: 100)),
                  _labeled(l10n.t('env.user'), _field(_dbUser, width: 160)),
                  _labeled(l10n.t('env.password'), _field(_dbPass, obscure: true, width: 180)),
                  _labeled(l10n.t('env.dbName'), _field(_dbName, width: 170)),
                ]),
              ),
              SettingRow(
                label: l10n.t('env.embed'),
                description: l10n.t('env.embedDesc'),
                stacked: true,
                control: Wrap(spacing: 12, runSpacing: 12, children: [
                  _labeled(
                    l10n.t('env.provider'),
                    SizedBox(
                      width: 220,
                      child: DropdownButtonFormField<String>(
                        initialValue: _provider,
                        decoration: const InputDecoration(isDense: true),
                        items: const [
                          DropdownMenuItem(value: 'local', child: Text('local')),
                          DropdownMenuItem(value: 'gemini', child: Text('Google Gemini')),
                          DropdownMenuItem(value: 'openai', child: Text('OpenAI')),
                          DropdownMenuItem(value: 'voyage', child: Text('Voyage')),
                        ],
                        onChanged: (v) => setState(() {
                          _provider = v ?? 'local';
                          _apiKey.text = _providerKeyValue();
                        }),
                      ),
                    ),
                  ),
                  if (_provider != 'local')
                    _labeled(l10n.t('env.apiKey'),
                        _field(_apiKey, obscure: true, width: 380)),
                ]),
              ),
              SettingRow(
                label: l10n.t('env.server'),
                description: l10n.t('env.serverDesc'),
                stacked: true,
                control: Wrap(spacing: 12, runSpacing: 12, children: [
                  _labeled(l10n.t('env.httpHost'), _field(_httpHost, width: 180)),
                  _labeled(l10n.t('env.httpPort'), _field(_httpPort, width: 100)),
                ]),
              ),
              SettingRow(
                label: l10n.t('env.token'),
                description: l10n.t('env.tokenDesc'),
                stacked: true,
                control: Row(children: [
                  Expanded(child: _field(_token, width: double.infinity)),
                  const SizedBox(width: 8),
                  OutlinedButton(
                      onPressed: _generateToken, child: Text(l10n.t('env.generate'))),
                ]),
              ),
              SettingRow(
                label: l10n.t('env.maint'),
                description: l10n.t('env.intervalDesc'),
                stacked: true,
                control: Wrap(spacing: 12, runSpacing: 12, children: [
                  _labeled(l10n.t('env.interval'), _field(_maintMin, width: 140)),
                  _labeled(l10n.t('env.metricsLabel'), _field(_metricsLabel, width: 200)),
                ]),
              ),
              // advanced raw editor
              Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text(l10n.t('env.advanced'),
                      style: const TextStyle(fontSize: 13, color: OracleBrand.gray400)),
                  children: [
                    TextField(
                      controller: _rawEnv,
                      maxLines: 12,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: OutlinedButton(
                          onPressed: () async {
                            final path = widget.connection.envPath;
                            if (path == null) return;
                            await File(path).writeAsString(_rawEnv.text, flush: true);
                            if (context.mounted) showSnack(context, l10n.t('set.envSaved'));
                          },
                          child: Text(l10n.t('set.envSave')),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── agent integration ──
          SectionCard(
            title: l10n.t('set.agents'),
            description: l10n.t('set.agentsDesc'),
            children: [
              SettingRow(
                label: l10n.t('set.mcpTitle'),
                stacked: true,
                control: _snippet(mcpSnippet, () => _copy(mcpSnippet, '.mcp.json')),
              ),
              SettingRow(
                label: l10n.t('set.targetsTitle'),
                stacked: true,
                control: MarkdownView(server.agentTargetsMarkdown(command: binPath)),
              ),
              SettingRow(
                label: l10n.t('set.hooksTitle'),
                stacked: true,
                control: _snippet(hooksSnippet, () => _copy(hooksSnippet, '"hooks"')),
              ),
              SettingRow(
                label: l10n.t('set.promptTitle'),
                description: l10n.t('set.promptDesc'),
                stacked: true,
                control: _snippet(
                    server.agentProtocol().trim(),
                    () => _copy(server.agentProtocol().trim(),
                        l10n.t('set.promptTitle'))),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _labeled(String label, Widget child) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 12, color: OracleBrand.gray400, fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          child,
        ],
      );

  Widget _snippet(String content, VoidCallback onCopy) => Stack(children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: OracleBrand.gray950,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: OracleBrand.gray700),
          ),
          child: SelectableText(content,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: IconButton(
            tooltip: l10n.t('set.copy'),
            onPressed: onCopy,
            icon: const Icon(Icons.copy, size: 16),
          ),
        ),
      ]);
}
