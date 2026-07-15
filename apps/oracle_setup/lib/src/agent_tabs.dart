import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:oracle_server/oracle_server.dart' as server;

import 'core/brand.dart';
import 'core/l10n.dart';

/// Per-agent integration tabs for the installer (Claude Code, Codex, Cursor, …).
/// Each tab shows that agent's MCP config, its hooks config (or a no-hooks note),
/// and which instruction file carries the shared protocol. Mirrors the Studio's
/// AgentTabs so the installer and the control center present the same wiring.
class AgentTabs extends StatefulWidget {
  final List<server.AgentIntegration> agents;
  const AgentTabs({super.key, required this.agents});

  @override
  State<AgentTabs> createState() => _AgentTabsState();
}

class _AgentTabsState extends State<AgentTabs> {
  int _sel = 0;

  void _copy(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(l10n.t('agents.copied'))));
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.agents[_sel];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (var i = 0; i < widget.agents.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(widget.agents[i].name),
                selected: _sel == i,
                onSelected: (_) => setState(() => _sel = i),
              ),
            ),
        ]),
      ),
      const SizedBox(height: 16),
      _pane(a),
    ]);
  }

  Widget _pane(server.AgentIntegration a) {
    return Column(
      key: ValueKey(a.id),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _badge(a),
        const SizedBox(height: 16),
        _label('${l10n.t('ag.mcp')} · ${a.mcpFile}'),
        _snippet(a.mcpSnippet),
        if (a.mcpCli != null) ...[
          const SizedBox(height: 8),
          _inline('${l10n.t('ag.cli')}: ', a.mcpCli!),
        ],
        const SizedBox(height: 20),
        _label('${l10n.t('ag.hooks')}${a.hooksFile != null ? ' · ${a.hooksFile}' : ''}'),
        _hookBody(a),
        const SizedBox(height: 20),
        _label(l10n.t('ag.instr')),
        _note('${l10n.t('ag.instrBody')} ${a.instructionFile}'),
      ],
    );
  }

  Widget _badge(server.AgentIntegration a) {
    final (String text, Color color) = switch (a.hooks) {
      server.HookSupport.http => (l10n.t('ag.badgeHttp'), OracleBrand.success),
      server.HookSupport.bridge => (l10n.t('ag.badgeBridge'), OracleBrand.violet),
      server.HookSupport.none => (l10n.t('ag.badgeNone'), OracleBrand.gray500),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(text, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
    );
  }

  Widget _hookBody(server.AgentIntegration a) {
    switch (a.hooks) {
      case server.HookSupport.http:
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _snippet(a.hooksSnippet!),
          const SizedBox(height: 6),
          _note(l10n.t('ag.hooksHttp')),
        ]);
      case server.HookSupport.bridge:
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _snippet(a.hooksSnippet!),
          const SizedBox(height: 6),
          _note(l10n.t('ag.hooksBridge')),
        ]);
      case server.HookSupport.none:
        return _note(l10n.t('ag.hooksNone'));
    }
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: const TextStyle(
                fontSize: 12, color: OracleBrand.gray400, fontWeight: FontWeight.w600)),
      );

  Widget _note(String text) =>
      Text(text, style: const TextStyle(fontSize: 12, color: OracleBrand.gray400, height: 1.4));

  Widget _inline(String prefix, String value) => Row(children: [
        Text(prefix, style: const TextStyle(fontSize: 12, color: OracleBrand.gray400)),
        Expanded(
          child:
              SelectableText(value, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
        ),
        IconButton(
          tooltip: l10n.t('agents.copy'),
          onPressed: () => _copy(value),
          icon: const Icon(Icons.copy, size: 15),
        ),
      ]);

  Widget _snippet(String content) => Stack(children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(12, 12, 40, 12),
          decoration: BoxDecoration(
            color: OracleBrand.surfaceHigh,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: OracleBrand.violet.withValues(alpha: 0.2)),
          ),
          child: SelectableText(content,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: IconButton(
            tooltip: l10n.t('agents.copy'),
            onPressed: () => _copy(content),
            icon: const Icon(Icons.copy, size: 16),
          ),
        ),
      ]);
}
