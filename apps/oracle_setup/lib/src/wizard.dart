import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/brand.dart';
import 'core/l10n.dart';
import 'setup_state.dart';

/// The installation wizard: brand rail on the left (logo + steps + language),
/// the active step on the right, Voltar/Avançar below. Every action delegates
/// to [SetupState].
class SetupWizard extends StatefulWidget {
  const SetupWizard({super.key});

  @override
  State<SetupWizard> createState() => _SetupWizardState();
}

class _SetupWizardState extends State<SetupWizard> {
  final _state = SetupState();
  int _step = 0;

  @override
  void initState() {
    super.initState();
    // Pre-probe Docker/existing-DB availability so the cards show live status
    // the moment the user reaches the database step.
    _state.detect();
  }

  /// Why "Avançar" is blocked on the database step — shown next to the button
  /// so the user always knows the missing action.
  String? get _blockedHint {
    if (_canAdvance) return null;
    if (_step == 2) {
      return switch (_state.dbMode) {
        DbMode.portable => l10n.t('db.hintPortable'),
        DbMode.docker => l10n.t('db.hintDocker'),
        DbMode.existing => l10n.t('db.hintExisting'),
      };
    }
    if (_step == 3) return l10n.t('embed.testHint');
    return null;
  }

  static const _stepKeys = [
    'step.welcome',
    'step.db',
    'step.dbSetup',
    'step.embed',
    'step.security',
    'step.install',
    'step.agents',
    'step.finish',
  ];

  bool get _canAdvance => switch (_step) {
        // Step 1 is the CHOICE only; the action lives in step 2 (dbSetup).
        2 => switch (_state.dbMode) {
            DbMode.existing => _state.existingOk == true,
            DbMode.docker => _state.dockerReady,
            DbMode.portable => _state.portableReady,
          },
        // API providers must pass the real "hello world" embedding test.
        3 => _state.embedderProvider == 'local' || _state.embedTested,
        5 => _state.installed,
        _ => true,
      };

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_state, l10n]),
      builder: (context, _) => Scaffold(
        body: Row(
          children: [
            // ── step rail ──
            Container(
              width: 232,
              color: OracleBrand.surface,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(bottom: 16),
                    child: Row(children: [
                      OracleLogo(size: 36),
                      SizedBox(width: 10),
                      GradientTitle('Oracle AI', style: TextStyle(fontSize: 18)),
                    ]),
                  ),
                  for (var i = 0; i < _stepKeys.length; i++)
                    ListTile(
                      dense: true,
                      leading: Icon(
                        i < _step
                            ? Icons.check_circle
                            : (i == _step ? Icons.radio_button_checked : Icons.circle_outlined),
                        size: 18,
                        color: i <= _step ? OracleBrand.violet : null,
                      ),
                      title: Text(l10n.t(_stepKeys[i])),
                      selected: i == _step,
                    ),
                  const Spacer(),
                  Row(children: [
                    const Icon(Icons.translate, size: 16),
                    const SizedBox(width: 8),
                    DropdownButton<String>(
                      value: l10n.code,
                      isDense: true,
                      underline: const SizedBox.shrink(),
                      items: const [
                        DropdownMenuItem(value: 'pt', child: Text('Português')),
                        DropdownMenuItem(value: 'en', child: Text('English')),
                      ],
                      onChanged: (v) => v == null ? null : l10n.set(v),
                    ),
                  ]),
                ],
              ),
            ),
            const VerticalDivider(width: 1),
            // ── active step ──
            Expanded(
              child: Column(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: switch (_step) {
                        0 => _welcome(context),
                        1 => _database(context),
                        2 => _dbSetup(context),
                        3 => _embedder(context),
                        4 => _security(context),
                        5 => _install(context),
                        6 => _agents(context),
                        _ => _finish(context),
                      },
                    ),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        if (_step > 0)
                          OutlinedButton(
                            onPressed: () => setState(() => _step--),
                            child: Text(l10n.t('nav.back')),
                          ),
                        const Spacer(),
                        if (_blockedHint != null) ...[
                          const Icon(Icons.info_outline,
                              size: 16, color: OracleBrand.warning),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              _blockedHint!,
                              style: const TextStyle(
                                  fontSize: 12, color: OracleBrand.gray400),
                            ),
                          ),
                          const SizedBox(width: 16),
                        ],
                        if (_step < _stepKeys.length - 1)
                          FilledButton(
                            onPressed: _canAdvance && !_state.busy
                                ? () => setState(() => _step++)
                                : null,
                            child: Text(l10n.t('nav.next')),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── steps ──

  Widget _welcome(BuildContext context) => ListView(children: [
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Image.asset('assets/logo.png', width: 220),
            ),
          ),
        ),
        Center(child: GradientTitle(l10n.t('welcome.title'))),
        const SizedBox(height: 16),
        Text(l10n.t('welcome.body')),
      ]);

  /// Step 1: CHOICE ONLY — stacked full-width cards, no actions here.
  Widget _database(BuildContext context) {
    final s = _state;
    Widget card(DbMode mode, IconData icon, String title, String desc, {Widget? badge}) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _ModeCard(
            selected: s.dbMode == mode,
            icon: icon,
            title: title,
            description: desc,
            badge: badge,
            onTap: () => setState(() => s.dbMode = mode),
          ),
        );
    return ListView(children: [
      GradientTitle(l10n.t('db.title')),
      const SizedBox(height: 4),
      Text(l10n.t('db.subtitle'), style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 16),
      card(DbMode.portable, Icons.all_inclusive, l10n.t('db.auto'), l10n.t('db.autoDesc'),
          badge: s.portableReady
              ? StatusBadge(l10n.t('db.ready'))
              : StatusBadge(l10n.t('db.autoBadge'), color: OracleBrand.violet)),
      card(DbMode.docker, Icons.directions_boat_outlined, l10n.t('db.dockerCard'),
          l10n.t('db.dockerCardDesc'),
          badge: s.dockerReady
              ? StatusBadge(l10n.t('db.ready'))
              : (s.dockerOk == false
                  ? StatusBadge(l10n.t('db.dockerMissing'), color: OracleBrand.warning)
                  : null)),
      card(DbMode.existing, Icons.storage_outlined, l10n.t('db.existingCard'),
          l10n.t('db.existingCardDesc'),
          badge: s.existingOk == true ? StatusBadge(l10n.t('db.ready')) : null),
    ]);
  }

  /// Step 2: the chosen mode's ACTION, big and unmissable.
  Widget _dbSetup(BuildContext context) {
    final s = _state;
    final ready = switch (s.dbMode) {
      DbMode.portable => s.portableReady,
      DbMode.docker => s.dockerReady,
      DbMode.existing => s.existingOk == true,
    };
    final (icon, title) = switch (s.dbMode) {
      DbMode.portable => (Icons.all_inclusive, l10n.t('db.auto')),
      DbMode.docker => (Icons.directions_boat_outlined, l10n.t('db.dockerCard')),
      DbMode.existing => (Icons.storage_outlined, l10n.t('db.existingCard')),
    };
    return ListView(children: [
      GradientTitle(l10n.t('step.dbSetup')),
      const SizedBox(height: 4),
      Text(l10n.t('dbs.subtitle'), style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 16),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: OracleBrand.violet.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 22, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                  child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
              if (ready)
                StatusBadge('${l10n.t('db.ready')}  localhost:${s.dbPort}'),
            ]),
            const SizedBox(height: 20),
            if (s.dbMode == DbMode.portable)
              FilledButton.icon(
                onPressed: s.busy || s.portableReady ? null : s.provisionPortable,
                icon: s.busy
                    ? const SizedBox(
                        width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(s.portableReady ? Icons.check : Icons.auto_awesome),
                label: Text(s.busy
                    ? l10n.t('db.installing')
                    : (s.portableReady ? l10n.t('db.installed') : l10n.t('db.install'))),
              )
            else if (s.dbMode == DbMode.docker)
              FilledButton.icon(
                onPressed: s.busy || s.dockerReady ? null : s.provisionDocker,
                icon: s.busy
                    ? const SizedBox(
                        width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(s.dockerReady ? Icons.check : Icons.play_arrow),
                label: Text(s.busy
                    ? l10n.t('db.dockerRunning')
                    : (s.dockerReady ? l10n.t('db.ready') : l10n.t('db.dockerRun'))),
              )
            else
              Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.end,
                  children: [
                    _tf(l10n.t('db.host'), s.dbHost, (v) => s.dbHost = v, width: 200),
                    _tf(l10n.t('db.port'), '${s.dbPort}',
                        (v) => s.dbPort = int.tryParse(v) ?? s.dbPort,
                        width: 100),
                    _tf(l10n.t('db.user'), s.dbUser, (v) => s.dbUser = v, width: 160),
                    _tf(l10n.t('db.password'), s.dbPassword, (v) => s.dbPassword = v,
                        width: 160, obscure: true),
                    _tf(l10n.t('db.name'), s.dbName, (v) => s.dbName = v, width: 160),
                    FilledButton(
                      onPressed: s.busy ? null : s.detect,
                      child: Text(s.busy ? l10n.t('db.testing') : l10n.t('db.test')),
                    ),
                    if (s.existingOk != null)
                      StatusBadge(
                        s.existingOk! ? l10n.t('db.connOk') : l10n.t('db.connFail'),
                        color: s.existingOk! ? OracleBrand.success : OracleBrand.error,
                      ),
                  ]),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      _logBox(context),
    ]);
  }

  Widget _embedder(BuildContext context) {
    final s = _state;
    return ListView(children: [
      GradientTitle(l10n.t('embed.title')),
      const SizedBox(height: 8),
      Text(l10n.t('embed.body')),
      const SizedBox(height: 16),
      DropdownButtonFormField<String>(
        initialValue: s.embedderProvider,
        decoration: InputDecoration(
            labelText: l10n.t('embed.provider'),
            border: const OutlineInputBorder(),
            isDense: true),
        items: [
          DropdownMenuItem(value: 'local', child: Text(l10n.t('embed.local'))),
          const DropdownMenuItem(value: 'gemini', child: Text('Google Gemini')),
          const DropdownMenuItem(value: 'openai', child: Text('OpenAI')),
          const DropdownMenuItem(value: 'voyage', child: Text('Voyage')),
        ],
        onChanged: (v) => setState(() {
          s.embedderProvider = v ?? 'local';
          s.embedTested = false;
          s.embedError = null;
        }),
      ),
      const SizedBox(height: 12),
      if (s.embedderProvider != 'local') ...[
        _tf(l10n.t('embed.key'), s.embedderApiKey, (v) {
          s.embedderApiKey = v;
          s.embedTested = false;
        }, width: 480, obscure: true),
        const SizedBox(height: 12),
        Row(children: [
          FilledButton.icon(
            onPressed: s.busy ? null : s.testEmbedding,
            icon: s.busy
                ? const SizedBox(
                    width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.bolt, size: 16),
            label: Text(s.busy ? l10n.t('embed.testing') : l10n.t('embed.test')),
          ),
          const SizedBox(width: 12),
          if (s.embedTested)
            StatusBadge('${l10n.t('embed.tested')}  ·  ${s.embedDims} dims'),
          if (s.embedError != null)
            Expanded(
              child: Text(s.embedError!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: OracleBrand.error, fontSize: 12)),
            ),
        ]),
      ],
    ]);
  }

  Widget _security(BuildContext context) {
    final s = _state;
    return ListView(children: [
      GradientTitle(l10n.t('sec.title')),
      const SizedBox(height: 8),
      Text(l10n.t('sec.body')),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(
          child: SelectableText(
            s.hookToken.isEmpty ? l10n.t('sec.none') : s.hookToken,
            style: const TextStyle(fontFamily: 'monospace'),
          ),
        ),
        const SizedBox(width: 12),
        FilledButton.tonal(onPressed: s.generateToken, child: Text(l10n.t('sec.generate'))),
        if (s.hookToken.isNotEmpty)
          IconButton(
            tooltip: l10n.t('sec.remove'),
            onPressed: () => setState(() => s.hookToken = ''),
            icon: const Icon(Icons.clear),
          ),
      ]),
    ]);
  }

  Widget _install(BuildContext context) {
    final s = _state;
    Widget row(IconData icon, String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 16, color: OracleBrand.gray400),
            const SizedBox(width: 10),
            SizedBox(
                width: 210,
                child: Text(label,
                    style: const TextStyle(fontSize: 12, color: OracleBrand.gray400))),
            Expanded(
                child: SelectableText(value, style: const TextStyle(fontSize: 12))),
          ]),
        );
    return ListView(children: [
      GradientTitle(l10n.t('inst.title')),
      const SizedBox(height: 4),
      Text(l10n.t('inst.summary'), style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 16),
      // Human summary — no raw .env; the file is written automatically.
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            row(Icons.folder_special_outlined, l10n.t('inst.location'), s.installRoot),
            row(Icons.storage_outlined, l10n.t('inst.dbSummary'),
                '${s.dbHost}:${s.dbPort} · ${s.dbName}'),
            row(Icons.bolt_outlined, l10n.t('inst.embedSummary'),
                s.embedderProvider == 'local'
                    ? 'local (offline)'
                    : '${s.embedderProvider} · ${l10n.t('embed.tested')}'),
            row(Icons.terminal, l10n.t('inst.mcpSummary'), s.installedCli),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      // Optional validated backup restore.
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l10n.t('inst.pickBackup'),
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(l10n.t('inst.pickBackupDesc'),
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            Row(children: [
              OutlinedButton.icon(
                onPressed: s.busy
                    ? null
                    : () async {
                        final file = await openFile(acceptedTypeGroups: [
                          const XTypeGroup(label: 'SQL', extensions: ['sql'])
                        ]);
                        if (file != null) await s.validateBackupFile(file.path);
                      },
                icon: const Icon(Icons.folder_open, size: 16),
                label: Text(l10n.t('inst.selectFile')),
              ),
              const SizedBox(width: 12),
              if (s.backupFile != null)
                Expanded(
                  child: Row(children: [
                    Flexible(
                      child: Text(s.backupFile!,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12, color: OracleBrand.gray400)),
                    ),
                    const SizedBox(width: 8),
                    StatusBadge(
                      s.backupValid == true
                          ? l10n.t('inst.backupOk')
                          : l10n.t('inst.backupBad'),
                      color: s.backupValid == true
                          ? OracleBrand.success
                          : OracleBrand.error,
                    ),
                  ]),
                ),
            ]),
          ]),
        ),
      ),
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: s.busy || s.installed ? null : s.apply,
        icon: s.busy
            ? const SizedBox(
                width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
            : Icon(s.installed ? Icons.check : Icons.rocket_launch),
        label: Text(s.busy
            ? l10n.t('inst.running')
            : (s.installed ? l10n.t('inst.done') : l10n.t('inst.installNow'))),
      ),
      const SizedBox(height: 8),
      _logBox(context),
    ]);
  }

  Widget _agents(BuildContext context) {
    final s = _state;
    return ListView(children: [
      GradientTitle(l10n.t('agents.title')),
      const SizedBox(height: 12),
      _snippet(context, l10n.t('agents.mcp'), s.mcpSnippet),
      const SizedBox(height: 12),
      _snippet(context, l10n.t('agents.hooks'), s.hooksSnippet),
    ]);
  }

  Widget _finish(BuildContext context) => ListView(children: [
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: OracleLogo(size: 96),
          ),
        ),
        Center(child: GradientTitle(l10n.t('finish.title'))),
        const SizedBox(height: 16),
        Text(l10n.t('finish.body')),
        const SizedBox(height: 24),
        Center(
          child: FilledButton.icon(
            onPressed: _state.launchInstalled,
            icon: const Icon(Icons.rocket_launch),
            label: Text(l10n.t('finish.open')),
          ),
        ),
      ]);

  // ── helpers ──

  Widget _tf(String label, String value, void Function(String) onChanged,
      {double width = 220, bool obscure = false}) {
    return SizedBox(
      width: width,
      child: TextFormField(
        initialValue: value,
        obscureText: obscure,
        onChanged: onChanged,
        decoration:
            InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true),
      ),
    );
  }

  Widget _logBox(BuildContext context) {
    if (_state.log.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 220),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: OracleBrand.surfaceHigh,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: OracleBrand.violet.withValues(alpha: 0.2)),
      ),
      child: SingleChildScrollView(
        reverse: true,
        child: SelectableText(
          _state.log.join('\n'),
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
        ),
      ),
    );
  }

  Widget _snippet(BuildContext context, String title, String content) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text(title, style: Theme.of(context).textTheme.labelLarge)),
        IconButton(
          tooltip: l10n.t('agents.copy'),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: content));
            ScaffoldMessenger.of(context)
              ..clearSnackBars()
              ..showSnackBar(SnackBar(content: Text(l10n.t('agents.copied'))));
          },
          icon: const Icon(Icons.copy, size: 18),
        ),
      ]),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: OracleBrand.surfaceHigh,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: OracleBrand.violet.withValues(alpha: 0.2)),
        ),
        child: SelectableText(content,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
      ),
    ]);
  }
}

/// Selectable installation-mode card (Untitled UI "radio card" pattern):
/// icon, title, supporting text and an optional status badge; the selected
/// card gets the brand border.
class _ModeCard extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String title;
  final String description;
  final Widget? badge;
  final VoidCallback onTap;
  const _ModeCard({
    required this.selected,
    required this.icon,
    required this.title,
    required this.description,
    this.badge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected ? OracleBrand.violet.withValues(alpha: 0.16) : OracleBrand.gray900,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            // Unselected cards keep a clearly visible Untitled-UI gray-600
            // border; selection swaps it for the brand violet.
            color: selected ? OracleBrand.violetSoft : const Color(0xFF475467),
            width: selected ? 2 : 1.5,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: OracleBrand.violet.withValues(alpha: 0.35),
                    blurRadius: 16,
                    spreadRadius: 1,
                  ),
                ]
              : const [],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Featured icon in a tinted square (Untitled UI pattern).
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: selected
                    ? OracleBrand.violet.withValues(alpha: 0.30)
                    : OracleBrand.gray800,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 22,
                  color: selected ? Colors.white : OracleBrand.gray400),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text(title,
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: selected ? Colors.white : OracleBrand.gray100)),
                    if (badge != null) ...[const SizedBox(width: 10), badge!],
                  ]),
                  const SizedBox(height: 4),
                  Text(description,
                      style: TextStyle(
                          fontSize: 12,
                          color: selected ? OracleBrand.gray100 : OracleBrand.gray400,
                          height: 1.5)),
                ],
              ),
            ),
            const SizedBox(width: 14),
            // Explicit radio indicator — no ambiguity about the selection.
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? OracleBrand.violet : Colors.transparent,
                border: Border.all(
                  color: selected ? OracleBrand.violetSoft : OracleBrand.gray500,
                  width: 2,
                ),
              ),
              child: selected
                  ? const Icon(Icons.check, size: 14, color: Colors.white)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
