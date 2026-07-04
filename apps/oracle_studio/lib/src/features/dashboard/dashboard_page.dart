import 'package:flutter/material.dart';
import 'package:oracle_core/oracle_core.dart';
import 'package:oracle_memory/oracle_memory.dart';

import '../../core/brand.dart';
import '../../core/fmt.dart';
import '../../core/l10n.dart';
import '../../core/oracle_connection.dart';
import '../../widgets/async_view.dart';

class _DashboardData {
  final Map<String, int> counts;
  final LintReport lint;
  final List<MetricsSummary> metrics;
  const _DashboardData({required this.counts, required this.lint, required this.metrics});
}

/// Overview: entity counts, memory-bank health (lint) and token metrics.
class DashboardPage extends StatefulWidget {
  final OracleConnection connection;
  const DashboardPage({super.key, required this.connection});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  late Future<_DashboardData> _future = _load();

  Future<_DashboardData> _load() async {
    final db = widget.connection.database!;
    const tables = [
      'products', 'projects', 'memories', 'rules', 'skills',
      'architectures', 'sessions', 'requests', 'messages', 'handoffs',
    ];
    final selects = tables.map((t) => '(SELECT count(*) FROM $t) AS $t').join(', ');
    final row = (await db.select(SqlStatement('SELECT $selects', const {}))).rows.first;
    final counts = {for (final t in tables) t: row[t]?.toInt() ?? 0};

    final lint = (await injector.get<LintUsecase>()()).getOrThrow();
    final metrics = (await injector.get<MetricsSummaryUsecase>()()).getOrDefault(const []);
    return _DashboardData(counts: counts, lint: lint, metrics: metrics);
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
            trailing: IconButton(
              tooltip: l10n.t('common.refresh'),
              onPressed: () => setState(() => _future = _load()),
              icon: const Icon(Icons.refresh),
            ),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _CountCard(l10n.t('dash.products'), data.counts['products']!,
                  Icons.inventory_2_outlined),
              _CountCard(l10n.t('dash.projects'), data.counts['projects']!,
                  Icons.folder_outlined),
              _CountCard(l10n.t('dash.memories'), data.counts['memories']!,
                  Icons.psychology_outlined),
              _CountCard(l10n.t('dash.rules'), data.counts['rules']!, Icons.rule_outlined),
              _CountCard(l10n.t('dash.skills'), data.counts['skills']!, Icons.school_outlined),
              _CountCard(l10n.t('dash.architectures'), data.counts['architectures']!,
                  Icons.account_tree_outlined),
              _CountCard(l10n.t('dash.sessions'), data.counts['sessions']!,
                  Icons.forum_outlined),
              _CountCard(l10n.t('dash.requests'), data.counts['requests']!,
                  Icons.question_answer_outlined),
              _CountCard(l10n.t('dash.messages'), data.counts['messages']!,
                  Icons.chat_outlined),
              _CountCard(l10n.t('dash.handoffs'), data.counts['handoffs']!,
                  Icons.swap_horiz_outlined),
            ],
          ),
          const SizedBox(height: 24),
          Text(l10n.t('dash.health'), style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  MetaChip(
                    data.lint.clean ? l10n.t('dash.healthy') : l10n.t('dash.attention'),
                    icon: data.lint.clean ? Icons.check_circle_outline : Icons.warning_amber,
                  ),
                  MetaChip('${data.lint.memoriesWithoutEmbedding} ${l10n.t('dash.memNoEmb')}'),
                  MetaChip('${data.lint.rulesWithoutEmbedding} ${l10n.t('dash.ruleNoEmb')}'),
                  MetaChip('${data.lint.requestsWithoutMessages} ${l10n.t('dash.reqNoMsg')}'),
                  MetaChip('${data.lint.vectorsWithStaleModel} ${l10n.t('dash.staleVec')}'),
                  MetaChip('${l10n.t('dash.model')}: ${data.lint.currentModel}',
                      icon: Icons.memory),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(l10n.t('dash.metrics'), style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: data.metrics.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(l10n.t('dash.noMetrics')),
                    )
                  : SingleChildScrollView(
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
                          for (final m in data.metrics)
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
          ),
        ],
      ),
    );
  }
}

class _CountCard extends StatelessWidget {
  final String label;
  final int count;
  final IconData icon;
  const _CountCard(this.label, this.count, this.icon);

  @override
  Widget build(BuildContext context) {
    return Card(
      child: SizedBox(
        width: 168,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ShaderMask(
                shaderCallback: (b) => OracleBrand.gradient.createShader(b),
                child: Icon(icon, size: 22, color: Colors.white),
              ),
              const SizedBox(height: 8),
              Text(fmtCompact(count), style: Theme.of(context).textTheme.headlineSmall),
              Text(label, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}
