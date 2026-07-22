import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:oracle_core/oracle_core.dart';
import 'package:oracle_memory/oracle_memory.dart';

import '../../core/brand.dart';
import '../../core/fmt.dart';
import '../../core/l10n.dart';
import '../../widgets/async_view.dart';
import '../../widgets/editor_dialog.dart';
import '../../widgets/records_toolbar.dart';
import 'flow_editor.dart';
import 'flow_guide_page.dart';
import 'flow_labels.dart';

/// Loop Engineering — the PROCESS list. Creation/editing happens in the
/// n8n-style [FlowEditorPage] (connected chain of steps); this page lists the
/// saved processes and renders the selected graph with friendly labels.
class FlowsPage extends StatefulWidget {
  final ValueNotifier<ProjectEntity?> project;
  const FlowsPage({super.key, required this.project});

  @override
  State<FlowsPage> createState() => _FlowsPageState();
}

class _FlowsPageState extends State<FlowsPage> {
  FlowEntity? _selected;
  Future<List<FlowEntity>>? _future;
  int _detailRefresh = 0;
  final _query = TextEditingController();
  String _agent = 'all';

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

  void _reload({FlowEntity? select}) {
    final project = widget.project.value;
    if (project == null) return;
    setState(() {
      _selected = select ?? _selected;
      _detailRefresh++;
      _future = injector
          .get<ListFlowsUsecase>()(
            organizationId: project.organizationId,
            projectId: project.id,
            limit: 100,
          )
          .then((r) => r.getOrThrow());
    });
  }

  Future<void> _openEditor({
    FlowGraph? initial,
    List<StepDraft>? seed,
    List<(String, String, String, String?, String?)>? seedEdges,
    String? seedKey,
    String? seedName,
  }) async {
    final project = widget.project.value;
    if (project == null) return;
    final saved = await Navigator.of(context).push<FlowEntity>(
      MaterialPageRoute(
        builder: (_) => FlowEditorPage(
          project: project,
          initial: initial,
          seed: seed,
          seedEdges: seedEdges,
          seedKey: seedKey,
          seedName: seedName,
        ),
      ),
    );
    if (saved != null && mounted) {
      showSnack(context, l10n.t('flows.saved'));
      _reload(select: saved);
    }
  }

  Future<void> _editSelected() async {
    final flow = _selected;
    if (flow == null) return;
    final graph = await injector.get<GetFlowUsecase>()(id: flow.id).then(
      (r) => r.getOrThrow(),
    );
    if (!mounted) return;
    await _openEditor(initial: graph);
  }

  /// One-click "full feature" template — opens the editor pre-seeded with the
  /// COMPLETE RFC round loop: plan → create RFC → review → consolidate+plan →
  /// round gate (continuar loops back to review; concluir proceeds to dev;
  /// limite parks at the human gate) → dev → DECISION (tests: reprovado loops
  /// back to dev; aprovado proceeds) → docs → PR → human approval.
  void _template() {
    _openEditor(
      seedKey: 'feature-completa',
      seedName: l10n.t('flows.tplName'),
      seed: [
        StepDraft.of(
          key: 'plan',
          name: l10n.t('flows.tplPlanName'),
          kind: FlowStepKind.orchestrator,
          role: 'architect',
          prompt: l10n.t('flows.tplPlanPrompt'),
          x: 60,
          y: 160,
        ),
        StepDraft.of(
          key: 'rfc',
          name: l10n.t('flows.tplRfcName'),
          kind: FlowStepKind.rfcCreate,
          role: 'spec-author',
          x: 340,
          y: 160,
        ),
        StepDraft.of(
          key: 'review',
          name: l10n.t('flows.tplReviewName'),
          kind: FlowStepKind.rfcReview,
          agent: 'codex',
          role: 'reviewer',
          x: 620,
          y: 160,
        ),
        StepDraft.of(
          key: 'consolidar',
          name: l10n.t('flows.tplConsName'),
          kind: FlowStepKind.rfcConsolidate,
          role: 'consolidator',
          x: 900,
          y: 160,
        ),
        StepDraft.of(
          key: 'rodadas',
          name: l10n.t('flows.tplRoundsName'),
          kind: FlowStepKind.rfcGate,
          x: 1180,
          y: 160,
        ),
        StepDraft.of(
          key: 'dev',
          name: l10n.t('flows.tplDevName'),
          kind: FlowStepKind.agent,
          role: 'implementer',
          prompt: l10n.t('flows.presetPrompt.dev'),
          exit: 'dart analyze, dart test',
          x: 340,
          y: 430,
        ),
        StepDraft.of(
          key: 'testes',
          name: l10n.t('flows.tplTestName'),
          kind: FlowStepKind.decision,
          role: 'qa',
          prompt: l10n.t('flows.tplTestPrompt'),
          x: 620,
          y: 430,
        ),
        StepDraft.of(
          key: 'docs',
          name: l10n.t('flows.tplDocsName'),
          kind: FlowStepKind.agent,
          agent: 'codex',
          role: 'docs',
          prompt: l10n.t('flows.presetPrompt.docs'),
          x: 900,
          y: 430,
        ),
        StepDraft.of(
          key: 'pr',
          name: l10n.t('flows.tplPrName'),
          kind: FlowStepKind.agent,
          agent: 'gemini',
          role: 'release',
          prompt: l10n.t('flows.presetPrompt.pr'),
          x: 1180,
          y: 430,
        ),
        StepDraft.of(
          key: 'gate',
          name: l10n.t('flows.tplGateName'),
          kind: FlowStepKind.humanGate,
          x: 1460,
          y: 430,
        ),
      ],
      seedEdges: [
        ('plan', 'rfc', 'success', null, null),
        ('rfc', 'review', 'success', null, null),
        ('review', 'consolidar', 'success', null, null),
        ('consolidar', 'rodadas', 'success', null, null),
        (
          'rodadas',
          'review',
          'verdict',
          'continuar',
          l10n.t('flows.tplEdgeContinuar'),
        ),
        (
          'rodadas',
          'dev',
          'verdict',
          'concluir',
          l10n.t('flows.tplEdgeConcluir'),
        ),
        ('rodadas', 'gate', 'verdict', 'limite', l10n.t('flows.tplEdgeLimite')),
        ('dev', 'testes', 'success', null, null),
        (
          'testes',
          'dev',
          'verdict',
          'reprovado',
          l10n.t('flows.tplEdgeReprovado'),
        ),
        (
          'testes',
          'docs',
          'verdict',
          'aprovado',
          l10n.t('flows.tplEdgeAprovado'),
        ),
        ('docs', 'pr', 'success', null, null),
        ('pr', 'gate', 'success', null, null),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_future == null) {
      return Center(child: Text(l10n.t('common.selectProject')));
    }
    return AsyncView<List<FlowEntity>>(
      future: _future!,
      onRetry: _reload,
      builder: (context, flows) {
        final q = _query.text.trim().toLowerCase();
        final agents = flows.map((f) => f.orchestratorAgent).toSet().toList()
          ..sort();
        final filtered = flows
            .where(
              (f) =>
                  (_agent == 'all' || f.orchestratorAgent == _agent) &&
                  (q.isEmpty ||
                      f.name.value.toLowerCase().contains(q) ||
                      f.key.toLowerCase().contains(q) ||
                      f.description.toLowerCase().contains(q) ||
                      f.orchestratorAgent.toLowerCase().contains(q)),
            )
            .toList();
        return Column(
          children: [
            RecordsToolbar(
              title: l10n.t('nav.flows'),
              description: l10n.t('nav.flowsHint'),
              searchController: _query,
              onSearchChanged: (_) => setState(() {}),
              onRefresh: _reload,
              resultCount: filtered.length,
              filters: [
                ChoiceChip(
                  label: Text(l10n.t('records.all')),
                  selected: _agent == 'all',
                  onSelected: (_) => setState(() => _agent = 'all'),
                ),
                for (final agent in agents)
                  ChoiceChip(
                    label: Text(agentLabel(agent)),
                    selected: _agent == agent,
                    onSelected: (_) => setState(() => _agent = agent),
                  ),
              ],
              actions: [
                TextButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const FlowGuidePage()),
                  ),
                  icon: const Icon(Icons.help_outline, size: 18),
                  label: Text(l10n.t('flows.guide')),
                ),
                OutlinedButton.icon(
                  onPressed: _template,
                  icon: const Icon(Icons.auto_awesome_outlined),
                  label: Text(l10n.t('flows.template')),
                ),
                FilledButton.icon(
                  onPressed: () => _openEditor(),
                  icon: const Icon(Icons.add),
                  label: Text(l10n.t('flows.new')),
                ),
              ],
            ),
            Expanded(
              child: filtered.isEmpty
                  ? RecordsEmptyState(
                      title: flows.isEmpty
                          ? l10n.t('flows.empty')
                          : l10n.t('records.noMatch'),
                      description: flows.isEmpty
                          ? null
                          : l10n.t('records.noMatchHint'),
                      icon: Icons.account_tree_outlined,
                      action: flows.isEmpty
                          ? FilledButton.icon(
                              onPressed: _template,
                              icon: const Icon(Icons.auto_awesome_outlined),
                              label: Text(l10n.t('flows.template')),
                            )
                          : null,
                    )
                  : MasterDetail(
                      master: ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (context, i) {
                          final f = filtered[i];
                          return ListTile(
                            selected: _selected?.id.value == f.id.value,
                            leading: const Icon(
                              Icons.account_tree_outlined,
                              size: 20,
                            ),
                            title: Text(
                              f.name.value,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '${f.key} · v${f.versionNo} · ${agentLabel(f.orchestratorAgent)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Text(
                              fmtDateTime(f.updatedAt ?? f.createdAt),
                              style: const TextStyle(
                                fontSize: 11,
                                color: OracleBrand.gray500,
                              ),
                            ),
                            onTap: () => setState(() => _selected = f),
                          );
                        },
                      ),
                      detail: _selected == null
                          ? Center(child: Text(l10n.t('flows.selectOne')))
                          : _FlowDetail(
                              key: ValueKey(
                                '${_selected!.id.value}#$_detailRefresh',
                              ),
                              flow: _selected!,
                              onEdit: _editSelected,
                            ),
                    ),
            ),
          ],
        );
      },
    );
  }
}

/// Renders a saved process graph: meta, the connected chain preview, each step's
/// card and the connections — all with friendly labels.
class _FlowDetail extends StatefulWidget {
  final FlowEntity flow;
  final VoidCallback onEdit;
  const _FlowDetail({super.key, required this.flow, required this.onEdit});

  @override
  State<_FlowDetail> createState() => _FlowDetailState();
}

class _FlowDetailState extends State<_FlowDetail> {
  late Future<FlowGraph> _future;

  @override
  void initState() {
    super.initState();
    _future = injector.get<GetFlowUsecase>()(id: widget.flow.id).then(
      (r) => r.getOrThrow(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AsyncView<FlowGraph>(
      future: _future,
      builder: (context, graph) {
        final byId = {for (final s in graph.steps) s.id.value: s.stepKey};
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    graph.flow.name.value,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: widget.onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 17),
                  label: Text(l10n.t('flows.edit')),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                MetaChip(graph.flow.key, icon: Icons.tag),
                MetaChip('v${graph.flow.versionNo}', icon: Icons.history),
                MetaChip(
                  agentLabel(graph.flow.orchestratorAgent),
                  icon: Icons.hub_outlined,
                ),
                MetaChip(
                  '${graph.steps.length} ${l10n.t('flows.stepsShort')}',
                  icon: Icons.layers_outlined,
                ),
              ],
            ),
            if (graph.flow.description.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                graph.flow.description,
                style: const TextStyle(
                  fontSize: 13,
                  color: OracleBrand.gray400,
                ),
              ),
            ],
            const SizedBox(height: 14),
            // chain preview
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < graph.steps.length; i++) ...[
                    if (i > 0)
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 6),
                        child: Icon(
                          Icons.arrow_forward,
                          size: 16,
                          color: OracleBrand.gray500,
                        ),
                      ),
                    _chainChip(graph.steps[i]),
                  ],
                ],
              ),
            ),
            const Divider(height: 30),
            Text(
              l10n.t('flows.steps'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            for (final s in graph.steps) _StepView(step: s),
            const Divider(height: 28),
            Text(
              l10n.t('flows.connections'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (graph.edges.isEmpty)
              Text(
                l10n.t('flows.noEdges'),
                style: const TextStyle(
                  fontSize: 12,
                  color: OracleBrand.gray400,
                ),
              ),
            for (final e in graph.edges)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    StatusBadge(
                      byId[e.fromStep.value] ?? '?',
                      color: OracleBrand.gray500,
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Icon(
                        Icons.arrow_forward,
                        size: 16,
                        color: OracleBrand.gray400,
                      ),
                    ),
                    StatusBadge(
                      byId[e.toStep.value] ?? '?',
                      color: OracleBrand.violet,
                    ),
                    const SizedBox(width: 10),
                    MetaChip(
                      e.verdictValue == null
                          ? conditionLabel(e.condition)
                          : '${conditionLabel(e.condition)}: ${e.verdictValue}',
                      icon: Icons.alt_route,
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _chainChip(FlowStepEntity s) {
    final color = kindColor(s.kind);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(kindIcon(s.kind), size: 15, color: color),
          const SizedBox(width: 6),
          Text(
            s.stepKey,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _StepView extends StatelessWidget {
  final FlowStepEntity step;
  const _StepView({required this.step});

  @override
  Widget build(BuildContext context) {
    final commands = _exitCommands(step.exitCriteria);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                StatusBadge(
                  '${step.position + 1}. ${step.stepKey}',
                  color: OracleBrand.blue,
                ),
                StatusBadge(kindLabel(step.kind), color: kindColor(step.kind)),
                if (step.agent != null)
                  MetaChip(
                    agentLabel(step.agent!),
                    icon: Icons.smart_toy_outlined,
                  ),
                if (step.role != null)
                  MetaChip(step.role!, icon: Icons.badge_outlined),
                MetaChip(
                  '${l10n.t('flows.fMaxIter')}: ${step.maxIterations}',
                  icon: Icons.loop,
                ),
                MetaChip(onFailLabel(step.onFail), icon: Icons.error_outline),
              ],
            ),
            if (step.name.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                step.name,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
            if (step.promptTemplate.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                step.promptTemplate,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: OracleBrand.gray400,
                ),
              ),
            ],
            if (commands.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                '${l10n.t('flows.verifier')}: ${commands.join(' · ')}',
                style: const TextStyle(
                  fontSize: 12,
                  color: OracleBrand.gray400,
                ),
              ),
            ],
            if (step.command != null) ...[
              const SizedBox(height: 6),
              Text(
                '\$ ${step.command}',
                style: const TextStyle(
                  fontSize: 12,
                  color: OracleBrand.gray400,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static List<String> _exitCommands(String exitCriteriaJson) {
    try {
      final j = jsonDecode(exitCriteriaJson);
      if (j is Map && j['commands'] is List) {
        return (j['commands'] as List).map((e) => e.toString()).toList();
      }
    } catch (_) {
      /* none */
    }
    return const [];
  }
}
