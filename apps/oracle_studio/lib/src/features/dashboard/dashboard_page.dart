import 'package:flutter/material.dart';
import 'package:oracle_core/oracle_core.dart';
import 'package:oracle_memory/oracle_memory.dart';

import '../../core/brand.dart';
import '../../core/fmt.dart';
import '../../core/l10n.dart';
import '../../core/oracle_connection.dart';
import '../../widgets/async_view.dart';

class _DashboardData {
  final Map<String, int> global;
  final Map<String, int>? project; // per-project counts (null when none selected)
  final ProjectEntity? projectEntity;
  final LintReport lint;
  final List<MetricsSummary> metrics;
  const _DashboardData({
    required this.global,
    required this.project,
    required this.projectEntity,
    required this.lint,
    required this.metrics,
  });
}

/// Overview: a per-project summary (the selected project's identity + scoped
/// counts), then the whole memory bank's totals, health (lint) and token
/// metrics.
class DashboardPage extends StatefulWidget {
  final OracleConnection connection;
  final ValueNotifier<ProjectEntity?> project;
  const DashboardPage({super.key, required this.connection, required this.project});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  late Future<_DashboardData> _future = _load();

  @override
  void initState() {
    super.initState();
    widget.project.addListener(_reload);
  }

  @override
  void dispose() {
    widget.project.removeListener(_reload);
    super.dispose();
  }

  void _reload() => setState(() => _future = _load());

  Future<_DashboardData> _load() async {
    final db = widget.connection.database!;
    const tables = [
      'products', 'projects', 'memories', 'rules', 'skills',
      'architectures', 'sessions', 'requests', 'messages', 'handoffs',
    ];
    final selects = tables.map((t) => '(SELECT count(*) FROM $t) AS $t').join(', ');
    final row = (await db.select(SqlStatement('SELECT $selects', const {}))).rows.first;
    final global = {for (final t in tables) t: row[t]?.toInt() ?? 0};

    final project = widget.project.value;
    Map<String, int>? projectCounts;
    if (project != null) {
      const q = '''
        SELECT
          (SELECT count(*) FROM memories WHERE project_id = :pid::uuid AND is_latest) AS memories,
          (SELECT count(*) FROM rules WHERE project_id = :pid::uuid AND is_latest) AS rules,
          (SELECT count(*) FROM architectures WHERE project_id = :pid::uuid AND is_latest) AS architectures,
          (SELECT count(*) FROM sessions WHERE project_id = :pid::uuid) AS sessions,
          (SELECT count(*) FROM requests r JOIN sessions s ON s.id = r.session_id
             WHERE s.project_id = :pid::uuid) AS requests,
          (SELECT count(*) FROM handoffs WHERE project_id = :pid::uuid) AS handoffs
      ''';
      final pr = (await db.select(SqlStatement(q, {'pid': project.id.value}))).rows.first;
      projectCounts = {
        for (final k in ['memories', 'rules', 'architectures', 'sessions', 'requests', 'handoffs'])
          k: pr[k]?.toInt() ?? 0,
      };
    }

    final lint = (await injector.get<LintUsecase>()()).getOrThrow();
    final metrics = (await injector.get<MetricsSummaryUsecase>()()).getOrDefault(const []);
    return _DashboardData(
      global: global,
      project: projectCounts,
      projectEntity: project,
      lint: lint,
      metrics: metrics,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AsyncView<_DashboardData>(
      future: _future,
      builder: (context, data) => ListView(
        padding: const EdgeInsets.all(24),
        children: [
          BrandHeader(
            l10n.t('dash.title'),
            subtitle: l10n.t('dash.subtitle'),
            trailing: OutlinedButton.icon(
              onPressed: _reload,
              icon: const Icon(Icons.refresh, size: 16),
              label: Text(l10n.t('common.refresh')),
            ),
          ),
          const SizedBox(height: 24),

          // ── per-project overview ──
          if (data.projectEntity != null) ...[
            _SectionLabel(l10n.t('dash.thisProject'), l10n.t('dash.thisProjectSub')),
            const SizedBox(height: 12),
            _ProjectCard(data.projectEntity!, data.project!),
            const SizedBox(height: 12),
            Wrap(spacing: 12, runSpacing: 12, children: [
              _MetricCard(l10n.t('dash.memories'), data.project!['memories']!,
                  Icons.psychology_outlined, l10n.t('dash.capMemories')),
              _MetricCard(l10n.t('dash.rules'), data.project!['rules']!,
                  Icons.rule_outlined, l10n.t('dash.capRules')),
              _MetricCard(l10n.t('dash.architectures'), data.project!['architectures']!,
                  Icons.account_tree_outlined, l10n.t('dash.capArch')),
              _MetricCard(l10n.t('dash.sessions'), data.project!['sessions']!,
                  Icons.forum_outlined, l10n.t('dash.capSessions')),
              _MetricCard(l10n.t('dash.requests'), data.project!['requests']!,
                  Icons.question_answer_outlined, l10n.t('dash.capRequests')),
              _MetricCard(l10n.t('dash.handoffs'), data.project!['handoffs']!,
                  Icons.swap_horiz_outlined, l10n.t('dash.capHandoffs')),
            ]),
            const SizedBox(height: 28),
          ],

          // ── whole memory bank ──
          _SectionLabel(l10n.t('dash.global'), l10n.t('dash.globalSub')),
          const SizedBox(height: 12),
          Wrap(spacing: 12, runSpacing: 12, children: [
            _MetricCard(l10n.t('dash.products'), data.global['products']!,
                Icons.inventory_2_outlined, null),
            _MetricCard(l10n.t('dash.projects'), data.global['projects']!,
                Icons.folder_outlined, null),
            _MetricCard(l10n.t('dash.memories'), data.global['memories']!,
                Icons.psychology_outlined, null),
            _MetricCard(l10n.t('dash.rules'), data.global['rules']!, Icons.rule_outlined, null),
            _MetricCard(l10n.t('dash.skills'), data.global['skills']!, Icons.school_outlined, null),
            _MetricCard(l10n.t('dash.architectures'), data.global['architectures']!,
                Icons.account_tree_outlined, null),
            _MetricCard(l10n.t('dash.sessions'), data.global['sessions']!,
                Icons.forum_outlined, null),
            _MetricCard(l10n.t('dash.requests'), data.global['requests']!,
                Icons.question_answer_outlined, null),
            _MetricCard(l10n.t('dash.messages'), data.global['messages']!,
                Icons.chat_outlined, null),
            _MetricCard(l10n.t('dash.handoffs'), data.global['handoffs']!,
                Icons.swap_horiz_outlined, null),
          ]),
          const SizedBox(height: 28),

          // ── health ──
          _SectionLabel(l10n.t('dash.health'), l10n.t('dash.healthSub')),
          const SizedBox(height: 12),
          _HealthCard(data.lint),
          const SizedBox(height: 28),

          // ── token metrics ──
          _SectionLabel(l10n.t('dash.metrics'), l10n.t('dash.metricsSub')),
          const SizedBox(height: 12),
          _MetricsCard(data.metrics),
        ],
      ),
    );
  }
}

/// A section title + one-line explanation (Untitled UI section header).
class _SectionLabel extends StatelessWidget {
  final String title;
  final String subtitle;
  const _SectionLabel(this.title, this.subtitle);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 2),
        Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

/// Identity card for the selected project: name, repo path, description, dates.
class _ProjectCard extends StatelessWidget {
  final ProjectEntity project;
  final Map<String, int> counts;
  const _ProjectCard(this.project, this.counts);

  @override
  Widget build(BuildContext context) {
    final path = project.repoPath;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: OracleBrand.gradient,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.folder_rounded, size: 22, color: Colors.white),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(project.name.value, style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 2),
                    Row(children: [
                      const Icon(Icons.terminal, size: 13, color: OracleBrand.gray500),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          (path == null || path.isEmpty) ? l10n.t('shell.noPath') : path,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12, fontFamily: 'monospace', color: OracleBrand.gray400),
                        ),
                      ),
                    ]),
                  ],
                ),
              ),
            ]),
            if (project.description?.value.isNotEmpty ?? false) ...[
              const SizedBox(height: 14),
              Text(project.description!.value,
                  style: Theme.of(context).textTheme.bodyMedium),
            ],
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (project.createdAt != null)
                MetaChip('${l10n.t('dash.created')}: ${fmtDateTime(project.createdAt)}',
                    icon: Icons.schedule),
              MetaChip('${counts['memories']} ${l10n.t('dash.memories').toLowerCase()}',
                  icon: Icons.psychology_outlined),
              MetaChip('${counts['rules']} ${l10n.t('dash.rules').toLowerCase()}',
                  icon: Icons.rule_outlined),
              MetaChip('${counts['sessions']} ${l10n.t('dash.sessions').toLowerCase()}',
                  icon: Icons.forum_outlined),
            ]),
          ],
        ),
      ),
    );
  }
}

/// Untitled UI metric card: tinted icon, big number, label and an optional
/// one-line caption explaining what it counts.
class _MetricCard extends StatelessWidget {
  final String label;
  final int count;
  final IconData icon;
  final String? caption;
  const _MetricCard(this.label, this.count, this.icon, this.caption);

  @override
  Widget build(BuildContext context) {
    return Card(
      // Fixed height so cards in a row line up regardless of caption length
      // (a 1- vs 2-line caption would otherwise make neighbours uneven).
      child: SizedBox(
        width: 200,
        height: caption == null ? 108 : 134,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: OracleBrand.violet.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 18, color: OracleBrand.violetSoft),
                ),
                const Spacer(),
                Text(fmtCompact(count),
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 10),
              Text(label,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
              if (caption != null) ...[
                const SizedBox(height: 2),
                Expanded(
                  child: Text(caption!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: OracleBrand.gray500)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Memory-bank health from the lint report — a status badge plus a checklist.
class _HealthCard extends StatelessWidget {
  final LintReport lint;
  const _HealthCard(this.lint);

  @override
  Widget build(BuildContext context) {
    Widget row(String label, int n, {bool goodWhenZero = true}) {
      final ok = goodWhenZero ? n == 0 : true;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          Icon(ok ? Icons.check_circle_outline : Icons.warning_amber_rounded,
              size: 16, color: ok ? OracleBrand.success : OracleBrand.warning),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: Theme.of(context).textTheme.bodyMedium)),
          Text('$n',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
        ]),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              StatusBadge(
                lint.clean ? l10n.t('dash.healthy') : l10n.t('dash.attention'),
                color: lint.clean ? OracleBrand.success : OracleBrand.warning,
              ),
              const Spacer(),
              MetaChip('${l10n.t('dash.model')}: ${lint.currentModel}', icon: Icons.memory),
            ]),
            const SizedBox(height: 4),
            row('${l10n.t('dash.memNoEmb')} — ${l10n.t('dash.memNoEmbSub')}',
                lint.memoriesWithoutEmbedding),
            const Divider(height: 1),
            row('${l10n.t('dash.ruleNoEmb')} — ${l10n.t('dash.ruleNoEmbSub')}',
                lint.rulesWithoutEmbedding),
            const Divider(height: 1),
            row('${l10n.t('dash.reqNoMsg')} — ${l10n.t('dash.reqNoMsgSub')}',
                lint.requestsWithoutMessages),
            const Divider(height: 1),
            row('${l10n.t('dash.staleVec')} — ${l10n.t('dash.staleVecSub')}',
                lint.vectorsWithStaleModel),
          ],
        ),
      ),
    );
  }
}

/// Token metrics (A/B by label) in a table, with an explanatory empty state.
class _MetricsCard extends StatelessWidget {
  final List<MetricsSummary> metrics;
  const _MetricsCard(this.metrics);

  @override
  Widget build(BuildContext context) {
    if (metrics.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(children: [
            const Icon(Icons.insights_outlined, size: 18, color: OracleBrand.gray500),
            const SizedBox(width: 10),
            Expanded(child: Text(l10n.t('dash.noMetrics'),
                style: Theme.of(context).textTheme.bodyMedium)),
          ]),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: [
              const DataColumn(label: Text('Label')),
              DataColumn(label: Text(l10n.t('dash.sessionsCol')), numeric: true),
              const DataColumn(label: Text('Input'), numeric: true),
              const DataColumn(label: Text('Output'), numeric: true),
              const DataColumn(label: Text('Cache read'), numeric: true),
              DataColumn(label: Text(l10n.t('dash.compactions')), numeric: true),
              const DataColumn(label: Text('Turns'), numeric: true),
            ],
            rows: [
              for (final m in metrics)
                DataRow(cells: [
                  DataCell(Text(m.label)),
                  DataCell(Text('${m.sessions}')),
                  DataCell(Text(fmtCompact(m.inputTokens))),
                  DataCell(Text(fmtCompact(m.outputTokens))),
                  DataCell(Text(fmtCompact(m.cacheReadTokens))),
                  DataCell(Text('${m.compactions}')),
                  DataCell(Text('${m.turns}')),
                ]),
            ],
          ),
        ),
      ),
    );
  }
}
