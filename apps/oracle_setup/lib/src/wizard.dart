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

  static const _stepKeys = [
    'step.welcome',
    'step.db',
    'step.embed',
    'step.security',
    'step.install',
    'step.agents',
    'step.finish',
  ];

  bool get _canAdvance => switch (_step) {
        1 => _state.dbMode == DbMode.existing
            ? _state.existingOk == true
            : _state.dbMode == DbMode.docker
                ? _state.dockerOk == true
                : _state.portableReady,
        4 => _state.installed,
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
                        2 => _embedder(context),
                        3 => _security(context),
                        4 => _install(context),
                        5 => _agents(context),
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

  Widget _database(BuildContext context) {
    final s = _state;
    return RadioGroup<DbMode>(
      groupValue: s.dbMode,
      onChanged: (v) => setState(() => s.dbMode = v!),
      child: ListView(children: [
        GradientTitle(l10n.t('db.title')),
        const SizedBox(height: 8),
        RadioListTile<DbMode>(
          value: DbMode.existing,
          title: Text(l10n.t('db.existing')),
          subtitle: Text(s.existingOk == null
              ? l10n.t('db.existingHint')
              : (s.existingOk! ? l10n.t('db.connOk') : l10n.t('db.connFail'))),
        ),
        if (s.dbMode == DbMode.existing)
          Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 8),
            child: Wrap(spacing: 12, runSpacing: 12, children: [
              _tf(l10n.t('db.host'), s.dbHost, (v) => s.dbHost = v, width: 200),
              _tf(l10n.t('db.port'), '${s.dbPort}',
                  (v) => s.dbPort = int.tryParse(v) ?? s.dbPort,
                  width: 100),
              _tf(l10n.t('db.user'), s.dbUser, (v) => s.dbUser = v, width: 160),
              _tf(l10n.t('db.password'), s.dbPassword, (v) => s.dbPassword = v,
                  width: 160, obscure: true),
              _tf(l10n.t('db.name'), s.dbName, (v) => s.dbName = v, width: 160),
              FilledButton.tonal(
                onPressed: s.busy ? null : s.detect,
                child: Text(s.busy ? l10n.t('db.testing') : l10n.t('db.test')),
              ),
            ]),
          ),
        RadioListTile<DbMode>(
          value: DbMode.docker,
          title: Text(l10n.t('db.docker')),
          subtitle: Text(s.dockerOk == null
              ? l10n.t('db.dockerHint')
              : (s.dockerOk! ? l10n.t('db.dockerOk') : l10n.t('db.dockerMissing'))),
        ),
        RadioListTile<DbMode>(
          value: DbMode.portable,
          title: Text(l10n.t('db.portable')),
          subtitle: Text(s.portableReady
              ? '${l10n.t('db.portableReady')}${s.dbPort}'
              : l10n.t('db.portableHint')),
        ),
        if (s.dbMode == DbMode.portable)
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              FilledButton.icon(
                onPressed: s.busy || s.portableReady ? null : s.provisionPortable,
                icon: const Icon(Icons.download),
                label: Text(s.busy
                    ? l10n.t('db.installing')
                    : (s.portableReady ? l10n.t('db.installed') : l10n.t('db.install'))),
              ),
              const SizedBox(height: 8),
              _logBox(context),
            ]),
          ),
      ]),
    );
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
        onChanged: (v) => setState(() => s.embedderProvider = v ?? 'local'),
      ),
      const SizedBox(height: 12),
      if (s.embedderProvider != 'local')
        _tf(l10n.t('embed.key'), s.embedderApiKey, (v) => s.embedderApiKey = v,
            width: 480, obscure: true),
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
    var restoreSeed = false;
    return StatefulBuilder(
      builder: (context, setLocal) => ListView(children: [
        GradientTitle(l10n.t('inst.title')),
        const SizedBox(height: 8),
        Text('${l10n.t('inst.target')}: ${s.envTargetPath}'),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: SelectableText(s.buildEnv(),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
          ),
        ),
        const SizedBox(height: 8),
        CheckboxListTile(
          value: restoreSeed,
          onChanged: (v) => setLocal(() => restoreSeed = v ?? false),
          title: Text(l10n.t('inst.seed')),
          controlAffinity: ListTileControlAffinity.leading,
        ),
        FilledButton.icon(
          onPressed: s.busy || s.installed ? null : () => s.apply(restoreSeed: restoreSeed),
          icon: const Icon(Icons.rocket_launch),
          label: Text(s.busy
              ? l10n.t('inst.running')
              : (s.installed ? l10n.t('inst.done') : l10n.t('inst.run'))),
        ),
        const SizedBox(height: 8),
        _logBox(context),
      ]),
    );
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
