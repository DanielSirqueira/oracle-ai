import 'package:flutter/material.dart';
import 'package:oracle_core/oracle_core.dart';
import 'package:oracle_memory/oracle_memory.dart';

import '../../core/fmt.dart';
import '../../widgets/async_view.dart';
import '../../widgets/editor_dialog.dart';

/// Browse and curate the rules that apply to the selected project. Editing
/// re-saves the same key (supersession, history kept); priority is an in-place
/// re-rank; retiring drops the rule from recall.
class RulesPage extends StatefulWidget {
  final ValueNotifier<ProjectEntity?> project;
  const RulesPage({super.key, required this.project});

  @override
  State<RulesPage> createState() => _RulesPageState();
}

class _RulesPageState extends State<RulesPage> {
  RuleEntity? _selectedRule;
  Future<List<RuleEntity>>? _future;

  @override
  void initState() {
    super.initState();
    widget.project.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    widget.project.removeListener(_reload);
    super.dispose();
  }

  void _reload() {
    final project = widget.project.value;
    if (project == null) return;
    setState(() {
      _selectedRule = null;
      _future = injector
          .get<RulesForTaskUsecase>()(RulesForTaskQuery(projectId: project.id, limit: 200))
          .then((r) => r.getOrThrow());
    });
  }

  Future<void> _editRule({RuleEntity? original}) async {
    final project = widget.project.value;
    if (project == null) return;
    final key = TextEditingController(text: original?.key ?? '');
    final scope = TextEditingController(text: original?.scope ?? '');
    final title = TextEditingController(text: original?.title.value ?? '');
    final content = TextEditingController(text: original?.content.value ?? '');
    final tags = TextEditingController(text: original?.tags.join(', ') ?? '');
    var severity = original?.severity.code ?? 'recommended';
    var priority = original?.priority ?? 50;

    final saved = await showEditorDialog(
      context,
      title: original == null ? 'Nova regra (do projeto)' : 'Refinar regra (nova versão)',
      fields: (context, setState) => [
        FieldRow('Key (slug estável — mesma key = atualiza)', key, enabled: original == null),
        FieldRow('Escopo (módulo/pasta/área)', scope),
        FieldRow('Título', title),
        FieldRow('Conteúdo', content, maxLines: 10),
        FieldRow('Tags (separadas por vírgula)', tags),
        Row(children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: severity,
              decoration: const InputDecoration(
                  labelText: 'Severidade', border: OutlineInputBorder(), isDense: true),
              items: const [
                DropdownMenuItem(value: 'required', child: Text('obrigatória')),
                DropdownMenuItem(value: 'recommended', child: Text('recomendada')),
              ],
              onChanged: (v) => severity = v ?? severity,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: StatefulBuilder(
              builder: (context, setSlider) => Row(children: [
                const Text('Prioridade'),
                Expanded(
                  child: Slider(
                    value: priority.toDouble(),
                    max: 100,
                    divisions: 20,
                    label: '$priority',
                    onChanged: (v) => setSlider(() => priority = v.round()),
                  ),
                ),
                Text('$priority'),
              ]),
            ),
          ),
        ]),
      ],
      onSave: () async {
        final result = await injector.get<SaveRuleUsecase>()(RuleEntity(
          id: const IdVO.empty(),
          // Keep the original owner on edit (a product rule stays a product
          // rule); new rules created here are project-scoped.
          projectId: original == null ? project.id : original.projectId,
          productId: original?.productId,
          key: key.text.trim(),
          scope: scope.text.trim(),
          title: TextVO(title.text),
          content: TextVO(content.text),
          severity: RuleSeverity.parse(severity),
          priority: priority,
          tags: parseTags(tags.text),
        ));
        return result.fold((_) => null, (f) => f.errorMessage);
      },
    );
    if (saved == true && mounted) {
      showSnack(context, original == null ? 'Regra criada.' : 'Regra refinada (nova versão).');
      _reload();
    }
  }

  Future<void> _setPriority(RuleEntity rule, int priority) async {
    final result = await injector.get<SetRulePriorityUsecase>()(rule.id, priority);
    if (!mounted) return;
    result.fold(
      (_) {
        showSnack(context, 'Prioridade ajustada para $priority.');
        _reload();
      },
      (f) => showSnack(context, 'Falha: ${f.errorMessage}'),
    );
  }

  Future<void> _retireRule(RuleEntity rule, {required bool hard}) async {
    final ok = await confirmAction(
      context,
      title: hard ? 'Apagar permanentemente?' : 'Aposentar regra?',
      message: hard
          ? 'A regra "${rule.title.value}" será APAGADA para sempre.'
          : 'A regra "${rule.title.value}" sai do recall, mas é mantida para auditoria.',
      okLabel: hard ? 'Apagar' : 'Aposentar',
      destructive: true,
    );
    if (!ok) return;
    final result = await injector
        .get<RetireRuleUsecase>()(rule.id, reason: 'via Oracle Studio', hard: hard);
    if (!mounted) return;
    result.fold(
      (_) {
        showSnack(context, hard ? 'Regra apagada.' : 'Regra aposentada.');
        _reload();
      },
      (f) => showSnack(context, 'Falha: ${f.errorMessage}'),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_future == null) return const Center(child: Text('Selecione um projeto.'));
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Text('Regras do projeto (com herança do produto)',
                  style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              FilledButton.icon(
                onPressed: () => _editRule(),
                icon: const Icon(Icons.add),
                label: const Text('Nova regra'),
              ),
            ],
          ),
        ),
        Expanded(
          child: AsyncView<List<RuleEntity>>(
            future: _future!,
            builder: (context, rules) => MasterDetail(
              master: ListView.builder(
                itemCount: rules.length,
                itemBuilder: (context, i) {
                  final r = rules[i];
                  return ListTile(
                    selected: _selectedRule?.id.value == r.id.value,
                    leading: Icon(
                      r.severity.code == 'required' ? Icons.gavel : Icons.tips_and_updates_outlined,
                      size: 20,
                    ),
                    title: Text(r.title.value, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${r.key} · ${r.scope} · prioridade ${r.priority}',
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () => setState(() => _selectedRule = r),
                  );
                },
              ),
              detail: _selectedRule == null
                  ? const Center(child: Text('Selecione uma regra.'))
                  : _RuleDetail(
                      rule: _selectedRule!,
                      onEdit: () => _editRule(original: _selectedRule),
                      onPriority: (p) => _setPriority(_selectedRule!, p),
                      onRetire: (hard) => _retireRule(_selectedRule!, hard: hard),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

class _RuleDetail extends StatelessWidget {
  final RuleEntity rule;
  final VoidCallback onEdit;
  final void Function(int priority) onPriority;
  final void Function(bool hard) onRetire;
  const _RuleDetail({
    required this.rule,
    required this.onEdit,
    required this.onPriority,
    required this.onRetire,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            Expanded(child: Text(rule.title.value, style: Theme.of(context).textTheme.titleLarge)),
            IconButton(tooltip: 'Refinar (nova versão)', onPressed: onEdit, icon: const Icon(Icons.edit_outlined)),
            PopupMenuButton<String>(
              tooltip: 'Aposentar',
              icon: const Icon(Icons.delete_outline),
              onSelected: (v) => onRetire(v == 'hard'),
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'soft', child: Text('Aposentar (mantém auditoria)')),
                PopupMenuItem(value: 'hard', child: Text('Apagar permanentemente')),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            MetaChip('key: ${rule.key}', icon: Icons.key),
            MetaChip('escopo: ${rule.scope}', icon: Icons.crop_free),
            MetaChip(
              rule.severity.code == 'required' ? 'obrigatória' : 'recomendada',
              icon: rule.severity.code == 'required' ? Icons.gavel : Icons.tips_and_updates_outlined,
            ),
            MetaChip(rule.projectId != null ? 'do projeto' : 'do produto (herdada)',
                icon: Icons.account_tree_outlined),
            MetaChip(fmtDateTime(rule.createdAt), icon: Icons.schedule),
            for (final t in rule.tags) MetaChip('#$t'),
          ],
        ),
        const SizedBox(height: 12),
        Row(children: [
          const Text('Prioridade'),
          Expanded(
            child: Slider(
              value: rule.priority.toDouble(),
              max: 100,
              divisions: 20,
              label: '${rule.priority}',
              onChanged: null, // display; use the button to apply
            ),
          ),
          Text('${rule.priority}'),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: () async {
              var p = rule.priority;
              final apply = await showDialog<bool>(
                context: context,
                builder: (context) => StatefulBuilder(
                  builder: (context, setState) => AlertDialog(
                    title: const Text('Re-ranquear regra'),
                    content: Row(mainAxisSize: MainAxisSize.min, children: [
                      SizedBox(
                        width: 320,
                        child: Slider(
                          value: p.toDouble(),
                          max: 100,
                          divisions: 20,
                          label: '$p',
                          onChanged: (v) => setState(() => p = v.round()),
                        ),
                      ),
                      Text('$p'),
                    ]),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancelar')),
                      FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Aplicar')),
                    ],
                  ),
                ),
              );
              if (apply == true) onPriority(p);
            },
            child: const Text('Ajustar'),
          ),
        ]),
        const Divider(height: 32),
        SelectableText(rule.content.value, style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}
