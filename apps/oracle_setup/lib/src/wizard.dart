import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'setup_state.dart';

/// The installation wizard: a fixed step rail on the left, the active step on
/// the right, Voltar/Avançar below. Every action delegates to [SetupState].
class SetupWizard extends StatefulWidget {
  const SetupWizard({super.key});

  @override
  State<SetupWizard> createState() => _SetupWizardState();
}

class _SetupWizardState extends State<SetupWizard> {
  final _state = SetupState();
  int _step = 0;

  static const _steps = [
    'Bem-vindo',
    'Banco de dados',
    'Embeddings',
    'Segurança',
    'Instalar',
    'Agentes',
    'Concluir',
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
      animation: _state,
      builder: (context, _) => Scaffold(
        body: Row(
          children: [
            // ── step rail ──
            Container(
              width: 220,
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(bottom: 16),
                    child: Row(children: [
                      Icon(Icons.auto_awesome, size: 22),
                      SizedBox(width: 8),
                      Text('Oracle AI', style: TextStyle(fontWeight: FontWeight.bold)),
                    ]),
                  ),
                  for (var i = 0; i < _steps.length; i++)
                    ListTile(
                      dense: true,
                      leading: Icon(
                        i < _step
                            ? Icons.check_circle
                            : (i == _step ? Icons.radio_button_checked : Icons.circle_outlined),
                        size: 18,
                        color: i <= _step ? Theme.of(context).colorScheme.primary : null,
                      ),
                      title: Text(_steps[i]),
                      selected: i == _step,
                    ),
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
                        if (_step > 0 && !_state.installed || _step == 5 || _step == 6)
                          OutlinedButton(
                            onPressed: _step > 0 ? () => setState(() => _step--) : null,
                            child: const Text('Voltar'),
                          ),
                        const Spacer(),
                        if (_step < _steps.length - 1)
                          FilledButton(
                            onPressed: _canAdvance && !_state.busy
                                ? () => setState(() => _step++)
                                : null,
                            child: const Text('Avançar'),
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
        Text('Bem-vindo ao Oracle AI', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        const Text('Este assistente instala e configura o banco de memória de longo prazo '
            'para os seus agentes de código (Claude Code, Codex, Cursor…).\n\n'
            'O que será feito:\n'
            '  1. Banco de dados (PostgreSQL + pgvector) — usa o seu, o Docker, ou '
            'instala um PostgreSQL portátil sem Docker;\n'
            '  2. Provedor de embeddings (local ou API);\n'
            '  3. Token de segurança dos hooks;\n'
            '  4. Migração do schema (e restauração de backup, se houver);\n'
            '  5. Configuração dos agentes (MCP + hooks).'),
      ]);

  Widget _database(BuildContext context) {
    final s = _state;
    return RadioGroup<DbMode>(
      groupValue: s.dbMode,
      onChanged: (v) => setState(() => s.dbMode = v!),
      child: ListView(children: [
      Text('Banco de dados', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 8),
      RadioListTile<DbMode>(
        value: DbMode.existing,
        title: const Text('Usar um PostgreSQL existente'),
        subtitle: Text(s.existingOk == null
            ? 'Informe os dados e teste a conexão.'
            : (s.existingOk! ? 'Conexão OK ✓' : 'Não conectou — confira os dados.')),
      ),
      if (s.dbMode == DbMode.existing)
        Padding(
          padding: const EdgeInsets.only(left: 16, bottom: 8),
          child: Wrap(spacing: 12, runSpacing: 12, children: [
            _tf('Host', s.dbHost, (v) => s.dbHost = v, width: 200),
            _tf('Porta', '${s.dbPort}', (v) => s.dbPort = int.tryParse(v) ?? s.dbPort,
                width: 100),
            _tf('Usuário', s.dbUser, (v) => s.dbUser = v, width: 160),
            _tf('Senha', s.dbPassword, (v) => s.dbPassword = v, width: 160, obscure: true),
            _tf('Banco', s.dbName, (v) => s.dbName = v, width: 160),
            FilledButton.tonal(
              onPressed: s.busy ? null : s.detect,
              child: Text(s.busy ? 'Testando…' : 'Testar conexão'),
            ),
          ]),
        ),
      RadioListTile<DbMode>(
        value: DbMode.docker,
        title: const Text('Docker (docker compose up)'),
        subtitle: Text(s.dockerOk == null
            ? 'Detecção pendente (botão "Testar conexão" também detecta o Docker).'
            : (s.dockerOk!
                ? 'Docker disponível ✓ — use docker compose up -d db no repositório.'
                : 'Docker não encontrado nesta máquina.')),
      ),
      RadioListTile<DbMode>(
        value: DbMode.portable,
        title: const Text('Instalar PostgreSQL portátil (sem Docker) — recomendado'),
        subtitle: Text(s.portableReady
            ? 'Pronto ✓ — localhost:${s.dbPort}'
            : 'Baixa/usa os binários oficiais + pgvector e cria um banco local do Oracle.'),
      ),
      if (s.dbMode == DbMode.portable)
        Padding(
          padding: const EdgeInsets.only(left: 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            FilledButton.icon(
              onPressed: s.busy || s.portableReady ? null : s.provisionPortable,
              icon: const Icon(Icons.download),
              label: Text(s.busy
                  ? 'Instalando…'
                  : (s.portableReady ? 'Instalado ✓' : 'Baixar e instalar agora')),
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
      Text('Embeddings', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 8),
      const Text('O provedor que transforma memórias em vetores para a busca semântica. '
          '"Local" funciona offline e sem custo; os provedores de API têm qualidade maior.'),
      const SizedBox(height: 16),
      DropdownButtonFormField<String>(
        initialValue: s.embedderProvider,
        decoration: const InputDecoration(
            labelText: 'Provedor', border: OutlineInputBorder(), isDense: true),
        items: const [
          DropdownMenuItem(value: 'local', child: Text('Local (offline, padrão)')),
          DropdownMenuItem(value: 'gemini', child: Text('Google Gemini')),
          DropdownMenuItem(value: 'openai', child: Text('OpenAI')),
          DropdownMenuItem(value: 'voyage', child: Text('Voyage')),
        ],
        onChanged: (v) => setState(() => s.embedderProvider = v ?? 'local'),
      ),
      const SizedBox(height: 12),
      if (s.embedderProvider != 'local')
        _tf('API key', s.embedderApiKey, (v) => s.embedderApiKey = v,
            width: 480, obscure: true),
    ]);
  }

  Widget _security(BuildContext context) {
    final s = _state;
    return ListView(children: [
      Text('Segurança', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 8),
      const Text('O token protege o endpoint /hook (que lê e escreve a memória). '
          'Opcional em uso estritamente local (loopback); obrigatório se a porta for exposta.'),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(
          child: SelectableText(
            s.hookToken.isEmpty ? '(sem token)' : s.hookToken,
            style: const TextStyle(fontFamily: 'monospace'),
          ),
        ),
        const SizedBox(width: 12),
        FilledButton.tonal(onPressed: s.generateToken, child: const Text('Gerar token')),
        if (s.hookToken.isNotEmpty)
          IconButton(
            tooltip: 'Remover',
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
        Text('Instalar', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text('Configuração será gravada em: ${s.envTargetPath}'),
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
          title: const Text('Restaurar backup (backups/oracle_seed.sql) se existir'),
          controlAffinity: ListTileControlAffinity.leading,
        ),
        FilledButton.icon(
          onPressed: s.busy || s.installed ? null : () => s.apply(restoreSeed: restoreSeed),
          icon: const Icon(Icons.rocket_launch),
          label: Text(s.busy
              ? 'Instalando…'
              : (s.installed ? 'Instalado ✓' : 'Gravar .env + migrar banco')),
        ),
        const SizedBox(height: 8),
        _logBox(context),
      ]),
    );
  }

  Widget _agents(BuildContext context) {
    final s = _state;
    return ListView(children: [
      Text('Conectar os agentes', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 12),
      _snippet(context, '.mcp.json (na raiz de cada projeto do agente)', s.mcpSnippet),
      const SizedBox(height: 12),
      _snippet(context, 'settings.json do Claude Code — bloco "hooks"', s.hooksSnippet),
    ]);
  }

  Widget _finish(BuildContext context) => ListView(children: [
        Text('Tudo pronto! 🎉', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        const Text('O Oracle AI está instalado e migrado.\n\n'
            'Próximos passos:\n'
            '  • Abra o Oracle Studio e ative "Iniciar com o Windows" (aba Config) — '
            'ele mantém hooks, manutenção e backups na bandeja;\n'
            '  • Cole os snippets da etapa anterior nos seus agentes;\n'
            '  • A primeira sessão de agente já grava memória compartilhada.'),
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
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
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
          tooltip: 'Copiar',
          onPressed: () {
            Clipboard.setData(ClipboardData(text: content));
            ScaffoldMessenger.of(context)
              ..clearSnackBars()
              ..showSnackBar(const SnackBar(content: Text('Copiado.')));
          },
          icon: const Icon(Icons.copy, size: 18),
        ),
      ]),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: SelectableText(content,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
      ),
    ]);
  }
}
