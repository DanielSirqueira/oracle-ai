import 'package:flutter/material.dart';
import 'package:oracle_core/oracle_core.dart';
import 'package:oracle_memory/oracle_memory.dart';

import '../../core/brand.dart';
import '../../core/fmt.dart';
import '../../core/l10n.dart';
import '../../widgets/async_view.dart';
import '../../widgets/editor_dialog.dart';
import '../../widgets/markdown_view.dart';
import '../../widgets/records_toolbar.dart';

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
  final _query = TextEditingController();
  String _severity = 'all';

  @override
  void initState() {
    super.initState();
    widget.project.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    widget.project.removeListener(_reload);
    _query.dispose();
    super.dispose();
  }

  void _reload() {
    final project = widget.project.value;
    if (project == null) return;
    setState(() {
      _selectedRule = null;
      _future = injector
          .get<RulesForTaskUsecase>()(
            RulesForTaskQuery(projectId: project.id, limit: 200),
          )
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
      title: original == null
          ? l10n.t('rule.newTitle')
          : l10n.t('rule.editTitle'),
      fields: (context, setState) => [
        FieldRow(
          l10n.t('rule.fieldKey'),
          key,
          enabled: original == null,
          description: l10n.t('rule.fieldKeyDesc'),
        ),
        FieldRow(
          l10n.t('rule.fieldScope'),
          scope,
          description: l10n.t('rule.fieldScopeDesc'),
        ),
        FieldRow(l10n.t('rule.fieldTitle'), title),
        FieldRow(
          l10n.t('rule.fieldContent'),
          content,
          maxLines: 10,
          description: l10n.t('rule.fieldContentDesc'),
        ),
        FieldRow(
          l10n.t('common.tags'),
          tags,
          description: l10n.t('common.tagsDesc'),
        ),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: severity,
                decoration: InputDecoration(
                  labelText: l10n.t('rule.severity'),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  DropdownMenuItem(
                    value: 'required',
                    child: Text(l10n.t('rule.required')),
                  ),
                  DropdownMenuItem(
                    value: 'recommended',
                    child: Text(l10n.t('rule.recommended')),
                  ),
                ],
                onChanged: (v) => severity = v ?? severity,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: StatefulBuilder(
                builder: (context, setSlider) => Row(
                  children: [
                    Text(l10n.t('rule.priority')),
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
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
      onSave: () async {
        final result = await injector.get<SaveRuleUsecase>()(
          RuleEntity(
            id: const IdVO.empty(),
            // Keep the original owner on edit (a organization rule stays a organization
            // rule); new rules created here are project-scoped.
            projectId: original == null ? project.id : original.projectId,
            organizationId: original?.organizationId,
            key: key.text.trim(),
            scope: scope.text.trim(),
            title: TextVO(title.text),
            content: TextVO(content.text),
            severity: RuleSeverity.parse(severity),
            priority: priority,
            tags: parseTags(tags.text),
          ),
        );
        return result.fold((_) => null, (f) => f.errorMessage);
      },
    );
    if (saved == true && mounted) {
      showSnack(
        context,
        original == null ? l10n.t('rule.created') : l10n.t('rule.refined'),
      );
      _reload();
    }
  }

  Future<void> _setPriority(RuleEntity rule, int priority) async {
    final result = await injector.get<SetRulePriorityUsecase>()(
      rule.id,
      priority,
    );
    if (!mounted) return;
    result.fold(
      (_) {
        showSnack(context, '${l10n.t('rule.prioritySet')} $priority.');
        _reload();
      },
      (f) =>
          showSnack(context, '${l10n.t('common.failure')}: ${f.errorMessage}'),
    );
  }

  Future<void> _retireRule(RuleEntity rule, {required bool hard}) async {
    final ok = await confirmAction(
      context,
      title: hard ? l10n.t('rule.deleteQ') : l10n.t('rule.retireQ'),
      message:
          '"${rule.title.value}" '
          '${hard ? l10n.t('rule.deleteMsg') : l10n.t('rule.retireMsg')}',
      okLabel: hard ? l10n.t('common.delete') : l10n.t('common.retire'),
      destructive: true,
    );
    if (!ok) return;
    final result = await injector.get<RetireRuleUsecase>()(
      rule.id,
      reason: 'via Oracle Studio',
      hard: hard,
    );
    if (!mounted) return;
    result.fold(
      (_) {
        showSnack(
          context,
          hard ? l10n.t('rule.deleted') : l10n.t('rule.retired'),
        );
        _reload();
      },
      (f) =>
          showSnack(context, '${l10n.t('common.failure')}: ${f.errorMessage}'),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_future == null) {
      return Center(child: Text(l10n.t('common.selectProject')));
    }
    return AsyncView<List<RuleEntity>>(
      future: _future!,
      onRetry: _reload,
      builder: (context, rules) {
        final q = _query.text.trim().toLowerCase();
        final filtered = rules.where((r) {
          final matchesText =
              q.isEmpty ||
              r.title.value.toLowerCase().contains(q) ||
              r.key.toLowerCase().contains(q) ||
              r.scope.toLowerCase().contains(q) ||
              r.tags.any((tag) => tag.toLowerCase().contains(q));
          return matchesText &&
              (_severity == 'all' || r.severity.code == _severity);
        }).toList();
        return Column(
          children: [
            RecordsToolbar(
              title: l10n.t('nav.rules'),
              description: l10n.t('nav.rulesHint'),
              searchController: _query,
              searchHint: l10n.t('records.search'),
              onSearchChanged: (_) => setState(() {}),
              onRefresh: _reload,
              resultCount: filtered.length,
              filters: [
                ChoiceChip(
                  label: Text(l10n.t('records.all')),
                  selected: _severity == 'all',
                  onSelected: (_) => setState(() => _severity = 'all'),
                ),
                ChoiceChip(
                  avatar: const Icon(Icons.gavel, size: 16),
                  label: Text(l10n.t('rule.required')),
                  selected: _severity == 'required',
                  onSelected: (_) => setState(() => _severity = 'required'),
                ),
                ChoiceChip(
                  avatar: const Icon(Icons.tips_and_updates_outlined, size: 16),
                  label: Text(l10n.t('rule.recommended')),
                  selected: _severity == 'recommended',
                  onSelected: (_) => setState(() => _severity = 'recommended'),
                ),
              ],
              actions: [
                FilledButton.icon(
                  onPressed: () => _editRule(),
                  icon: const Icon(Icons.add),
                  label: Text(l10n.t('rule.new')),
                ),
              ],
            ),
            Expanded(
              child: filtered.isEmpty
                  ? RecordsEmptyState(
                      title: l10n.t('records.noMatch'),
                      description: l10n.t('records.noMatchHint'),
                      icon: Icons.rule_outlined,
                    )
                  : MasterDetail(
                      master: ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (context, i) {
                          final r = filtered[i];
                          return ListTile(
                            selected: _selectedRule?.id.value == r.id.value,
                            leading: Icon(
                              r.severity.code == 'required'
                                  ? Icons.gavel
                                  : Icons.tips_and_updates_outlined,
                              size: 20,
                            ),
                            title: Text(
                              r.title.value,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '${r.key} · ${r.scope} · ${l10n.t('rule.priority').toLowerCase()} ${r.priority}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () => setState(() => _selectedRule = r),
                          );
                        },
                      ),
                      detail: _selectedRule == null
                          ? Center(child: Text(l10n.t('rule.selectOne')))
                          : _RuleDetail(
                              rule: _selectedRule!,
                              onEdit: () => _editRule(original: _selectedRule),
                              onPriority: (p) =>
                                  _setPriority(_selectedRule!, p),
                              onRetire: (hard) =>
                                  _retireRule(_selectedRule!, hard: hard),
                            ),
                    ),
            ),
          ],
        );
      },
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
            Expanded(
              child: Text(
                rule.title.value,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            IconButton(
              tooltip: l10n.t('rule.refine'),
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined),
            ),
            PopupMenuButton<String>(
              tooltip: l10n.t('common.retire'),
              icon: const Icon(Icons.delete_outline),
              onSelected: (v) => onRetire(v == 'hard'),
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'soft',
                  child: Text(l10n.t('common.retireSoft')),
                ),
                PopupMenuItem(
                  value: 'hard',
                  child: Text(l10n.t('common.deleteHard')),
                ),
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
            MetaChip(
              '${l10n.t('rule.scopeChip')}: ${rule.scope}',
              icon: Icons.crop_free,
            ),
            MetaChip(
              rule.severity.code == 'required'
                  ? l10n.t('rule.required')
                  : l10n.t('rule.recommended'),
              icon: rule.severity.code == 'required'
                  ? Icons.gavel
                  : Icons.tips_and_updates_outlined,
            ),
            MetaChip(
              rule.projectId != null
                  ? l10n.t('rule.fromProject')
                  : l10n.t('rule.fromOrganization'),
              icon: Icons.account_tree_outlined,
            ),
            MetaChip(fmtDateTime(rule.createdAt), icon: Icons.schedule),
            for (final t in rule.tags) MetaChip('#$t'),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          l10n.t('rule.priorityHint'),
          style: const TextStyle(fontSize: 12, color: OracleBrand.gray400),
        ),
        Row(
          children: [
            Text(l10n.t('rule.priority')),
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
                      title: Text(l10n.t('rule.rerank')),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            l10n.t('rule.priorityHint'),
                            style: const TextStyle(
                              fontSize: 12,
                              color: OracleBrand.gray400,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 320,
                                child: Slider(
                                  value: p.toDouble(),
                                  max: 100,
                                  divisions: 20,
                                  label: '$p',
                                  onChanged: (v) =>
                                      setState(() => p = v.round()),
                                ),
                              ),
                              Text('$p'),
                            ],
                          ),
                        ],
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: Text(l10n.t('common.cancel')),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: Text(l10n.t('common.apply')),
                        ),
                      ],
                    ),
                  ),
                );
                if (apply == true) onPriority(p);
              },
              child: Text(l10n.t('rule.adjust')),
            ),
          ],
        ),
        const Divider(height: 32),
        MarkdownView(rule.content.value),
      ],
    );
  }
}
