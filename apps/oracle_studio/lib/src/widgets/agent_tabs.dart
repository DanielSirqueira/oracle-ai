import 'package:flutter/material.dart';
import 'package:oracle_server/oracle_server.dart' as server;

import '../core/brand.dart';
import '../core/l10n.dart';

/// Per-agent integration tabs (Claude Code, Codex, Cursor, …). Each tab shows
/// that agent's MCP config, its hooks config (or a no-hooks note), and which
/// instruction file carries the shared protocol.
///
/// A plain selector + IndexedStack (not a [TabBarView]) so each pane sizes to its
/// content — the whole thing drops into a scrolling page with no fixed height.
class AgentTabs extends StatefulWidget {
  final List<server.AgentIntegration> agents;
  final void Function(String text, String label) onCopy;
  const AgentTabs({super.key, required this.agents, required this.onCopy});

  @override
  State<AgentTabs> createState() => _AgentTabsState();
}

class _AgentTabsState extends State<AgentTabs> {
  int _sel = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var i = 0; i < widget.agents.length; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(widget.agents[i].name),
                    selected: _sel == i,
                    onSelected: (_) => setState(() => _sel = i),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _AgentPane(widget.agents[_sel], onCopy: widget.onCopy),
      ],
    );
  }
}

class _AgentPane extends StatelessWidget {
  final server.AgentIntegration a;
  final void Function(String text, String label) onCopy;
  const _AgentPane(this.a, {required this.onCopy});

  @override
  Widget build(BuildContext context) {
    return Column(
      key: ValueKey(a.id),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _hookBadge(),
        const SizedBox(height: 16),

        // ── MCP ──
        _label('${l10n.t('ag.mcp')} · ${a.mcpFile}'),
        _snippet(a.mcpSnippet, () => onCopy(a.mcpSnippet, '${a.name} · MCP')),
        if (a.mcpCli != null) ...[
          const SizedBox(height: 8),
          _inline('${l10n.t('ag.cli')}: ', a.mcpCli!),
        ],
        const SizedBox(height: 20),

        // ── Hooks ──
        _label(
          '${l10n.t('ag.hooks')}${a.hooksFile != null ? ' · ${a.hooksFile}' : ''}',
        ),
        _hookBody(),
        const SizedBox(height: 20),

        // ── Instructions ──
        _label(l10n.t('ag.instr')),
        _note('${l10n.t('ag.instrBody')} ${a.instructionFile}'),
      ],
    );
  }

  Widget _hookBadge() {
    final (String text, Color color) = switch (a.hooks) {
      server.HookSupport.http => (l10n.t('ag.badgeHttp'), OracleBrand.success),
      server.HookSupport.bridge => (
        l10n.t('ag.badgeBridge'),
        OracleBrand.violet,
      ),
      server.HookSupport.none => (l10n.t('ag.badgeNone'), OracleBrand.gray500),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _hookBody() {
    switch (a.hooks) {
      case server.HookSupport.http:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _snippet(
              a.hooksSnippet!,
              () => onCopy(a.hooksSnippet!, '${a.name} · hooks'),
            ),
            const SizedBox(height: 6),
            _note(l10n.t('ag.hooksHttp')),
          ],
        );
      case server.HookSupport.bridge:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _snippet(
              a.hooksSnippet!,
              () => onCopy(a.hooksSnippet!, '${a.name} · hooks'),
            ),
            const SizedBox(height: 6),
            _note(l10n.t('ag.hooksBridge')),
          ],
        );
      case server.HookSupport.none:
        return _note(l10n.t('ag.hooksNone'));
    }
  }

  // ── small building blocks ──

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        color: OracleBrand.gray400,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  Widget _note(String text) => Text(
    text,
    style: const TextStyle(
      fontSize: 12,
      color: OracleBrand.gray400,
      height: 1.4,
    ),
  );

  Widget _inline(String prefix, String value) => Row(
    children: [
      Text(
        prefix,
        style: const TextStyle(fontSize: 12, color: OracleBrand.gray400),
      ),
      Expanded(
        child: SelectableText(
          value,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
        ),
      ),
      IconButton(
        tooltip: l10n.t('set.copy'),
        onPressed: () => onCopy(value, prefix),
        icon: const Icon(Icons.copy, size: 15),
      ),
    ],
  );

  Widget _snippet(String content, VoidCallback onCopyTap) => Stack(
    children: [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 12, 40, 12),
        decoration: BoxDecoration(
          color: OracleBrand.gray950,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: OracleBrand.gray700),
        ),
        child: SelectableText(
          content,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
        ),
      ),
      Positioned(
        top: 4,
        right: 4,
        child: IconButton(
          tooltip: l10n.t('set.copy'),
          onPressed: onCopyTap,
          icon: const Icon(Icons.copy, size: 16),
        ),
      ),
    ],
  );
}
