import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:oracle_server/oracle_server.dart' as server;

import '../../core/daemon_host.dart';
import '../../core/fmt.dart';
import '../../core/oracle_connection.dart';
import '../../widgets/editor_dialog.dart';

/// Settings: daemon hosting (hooks + maintenance), scheduled backups, agent
/// integration snippets (MCP + hooks) and the .env editor.
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

  @override
  void initState() {
    super.initState();
    final path = widget.connection.envPath;
    final content =
        (path != null && File(path).existsSync()) ? File(path).readAsStringSync() : '';
    _envController = TextEditingController(text: content)
      ..addListener(() => setState(() => _envDirty = true));
  }

  @override
  void dispose() {
    _envController.dispose();
    super.dispose();
  }

  Future<void> _saveEnv() async {
    final path = widget.connection.envPath;
    if (path == null) {
      showSnack(context, 'Nenhum .env conectado — crie um na raiz do projeto.');
      return;
    }
    await File(path).writeAsString(_envController.text, flush: true);
    if (!mounted) return;
    setState(() => _envDirty = false);
    showSnack(context, 'Salvo. Reinicie o Studio (e o MCP) para aplicar.');
  }

  void _copy(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    showSnack(context, '$label copiado para a área de transferência.');
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
          Text('Configurações', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),

          // ── daemon ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Daemon em segundo plano', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    'Com isto ligado, o Studio hospeda o receptor de hooks e o agendador de '
                    'manutenção — o oracle_ai.exe de console (serve-hooks) fica dispensado.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Hospedar hooks + manutenção neste app'),
                    subtitle: Text(daemon.hooksStatus),
                    value: settings.hostHooks,
                    onChanged: (v) {
                      settings.hostHooks = v;
                      daemon.applySettings();
                    },
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
                  Text('Backup agendado', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    'Snapshots .sql com carimbo de data em backups/ (com retenção). O seed '
                    'para commit/docker continua manual, na aba Backup.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Fazer backup automaticamente'),
                    value: settings.backupEnabled,
                    onChanged: (v) {
                      settings.backupEnabled = v;
                      daemon.applySettings();
                    },
                  ),
                  Row(children: [
                    const Text('A cada'),
                    const SizedBox(width: 12),
                    DropdownButton<int>(
                      value: settings.backupEveryHours,
                      items: const [
                        DropdownMenuItem(value: 6, child: Text('6 horas')),
                        DropdownMenuItem(value: 12, child: Text('12 horas')),
                        DropdownMenuItem(value: 24, child: Text('24 horas')),
                        DropdownMenuItem(value: 48, child: Text('48 horas')),
                      ],
                      onChanged: (v) {
                        settings.backupEveryHours = v ?? 24;
                        daemon.applySettings();
                      },
                    ),
                    const SizedBox(width: 24),
                    const Text('Manter últimos'),
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
                      label: Text(daemon.backingUp ? 'Executando…' : 'Executar agora'),
                    ),
                  ]),
                  if (daemon.lastBackupAt != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Último backup: ${fmtDateTime(daemon.lastBackupAt)} — ${daemon.lastBackupInfo}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  if (daemon.lastBackupError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text('Falha: ${daemon.lastBackupError}',
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
                  Text('Integração de agentes', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  _SnippetBlock(
                    title: '.mcp.json (raiz do projeto do agente)',
                    snippet: mcpSnippet,
                    onCopy: () => _copy(mcpSnippet, '.mcp.json'),
                  ),
                  const SizedBox(height: 12),
                  _SnippetBlock(
                    title: 'settings.json do Claude Code (bloco "hooks")',
                    snippet: hooksSnippet,
                    onCopy: () => _copy(hooksSnippet, 'Bloco de hooks'),
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
                    Text(widget.connection.envPath ?? '(não encontrado)',
                        style: Theme.of(context).textTheme.bodySmall),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: _envDirty ? _saveEnv : null,
                      icon: const Icon(Icons.save),
                      label: const Text('Salvar .env'),
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
          IconButton(tooltip: 'Copiar', onPressed: onCopy, icon: const Icon(Icons.copy, size: 18)),
        ]),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
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
