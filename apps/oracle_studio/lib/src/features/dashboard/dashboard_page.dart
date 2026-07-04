import 'package:flutter/material.dart';
import 'package:oracle_core/oracle_core.dart';
import 'package:oracle_memory/oracle_memory.dart';

import '../../core/fmt.dart';
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
    final selects =
        tables.map((t) => '(SELECT count(*) FROM $t) AS $t').join(', ');
    final row = (await db.select(SqlStatement('SELECT $selects', const {}))).rows.first;
    final counts = {for (final t in tables) t: row[t]?.toInt() ?? 0};

    final lint = (await injector.get<LintUsecase>()()).getOrThrow();
    final metrics =
        (await injector.get<MetricsSummaryUsecase>()()).getOrDefault(const []);
    return _DashboardData(counts: counts, lint: lint, metrics: metrics);
  }

  @override
  Widget build(BuildContext context) {
    return AsyncView<_DashboardData>(
      future: _future,
      builder: (context, data) => RefreshIndicator(
        onRefresh: () async => setState(() => _future = _load()),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Row(
              children: [
                Text('Visão geral', style: Theme.of(context).textTheme.headlineSmall),
                const Spacer(),
                IconButton(
                  tooltip: 'Atualizar',
                  onPressed: () => setState(() => _future = _load()),
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _CountCard('Produtos', data.counts['products']!, Icons.inventory_2_outlined),
                _CountCard('Projetos', data.counts['projects']!, Icons.folder_outlined),
                _CountCard('Memórias', data.counts['memories']!, Icons.psychology_outlined),
                _CountCard('Regras', data.counts['rules']!, Icons.rule_outlined),
                _CountCard('Skills', data.counts['skills']!, Icons.school_outlined),
                _CountCard('Arquiteturas', data.counts['architectures']!, Icons.account_tree_outlined),
                _CountCard('Sessões', data.counts['sessions']!, Icons.forum_outlined),
                _CountCard('Demandas', data.counts['requests']!, Icons.question_answer_outlined),
                _CountCard('Mensagens', data.counts['messages']!, Icons.chat_outlined),
                _CountCard('Handoffs', data.counts['handoffs']!, Icons.swap_horiz_outlined),
              ],
            ),
            const SizedBox(height: 24),
            Text('Saúde do banco de memória', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    MetaChip(
                      data.lint.clean ? 'Tudo saudável' : 'Atenção necessária',
                      icon: data.lint.clean ? Icons.check_circle_outline : Icons.warning_amber,
                    ),
                    MetaChip('${data.lint.memoriesWithoutEmbedding} memórias sem embedding'),
                    MetaChip('${data.lint.rulesWithoutEmbedding} regras sem embedding'),
                    MetaChip('${data.lint.requestsWithoutMessages} demandas sem resposta'),
                    MetaChip('${data.lint.vectorsWithStaleModel} vetores de modelo antigo'),
                    MetaChip('modelo atual: ${data.lint.currentModel}', icon: Icons.memory),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text('Métricas por experimento', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: data.metrics.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('Sem métricas registradas ainda.'),
                      )
                    : SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columns: const [
                            DataColumn(label: Text('Label')),
                            DataColumn(label: Text('Sessões'), numeric: true),
                            DataColumn(label: Text('Input'), numeric: true),
                            DataColumn(label: Text('Output'), numeric: true),
                            DataColumn(label: Text('Cache read'), numeric: true),
                            DataColumn(label: Text('Compactações'), numeric: true),
                            DataColumn(label: Text('Turns'), numeric: true),
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
              Icon(icon, size: 20),
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
