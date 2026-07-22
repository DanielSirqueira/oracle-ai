import 'package:flutter/material.dart';
import 'package:oracle_core/oracle_core.dart';
import 'package:oracle_memory/oracle_memory.dart';

import '../../core/brand.dart';
import '../../core/fmt.dart';
import '../../core/l10n.dart';
import '../../widgets/async_view.dart';
import '../../widgets/markdown_view.dart';
import '../../widgets/records_toolbar.dart';

/// Search history: every recall the agents made — the tool, the query, the scope
/// it ran under, and what came back (ids + scores). Lets you audit whether
/// retrieval is delivering what was asked; searches that returned NOTHING are
/// flagged as gaps in the memory bank.
class SearchHistoryPage extends StatefulWidget {
  final ValueNotifier<ProjectEntity?> project;
  const SearchHistoryPage({super.key, required this.project});

  @override
  State<SearchHistoryPage> createState() => _SearchHistoryPageState();
}

class _SearchHistoryPageState extends State<SearchHistoryPage> {
  AgentSearchEntity? _selected;
  bool _onlyGaps = false;
  Future<List<AgentSearchEntity>>? _future;
  final _query = TextEditingController();
  String _tool = 'all';

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
      _selected = null;
      _future = injector
          .get<RecentSearchesUsecase>()(project.id, limit: 300)
          .then((r) => r.getOrThrow());
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_future == null) {
      return Center(child: Text(l10n.t('common.selectProject')));
    }
    return Column(
      children: [
        Expanded(
          child: AsyncView<List<AgentSearchEntity>>(
            future: _future!,
            builder: (context, all) {
              final q = _query.text.trim().toLowerCase();
              final tools = all.map((s) => s.tool).toSet().toList()..sort();
              final list = all
                  .where(
                    (s) =>
                        (!_onlyGaps || s.hits == 0) &&
                        (_tool == 'all' || s.tool == _tool) &&
                        (q.isEmpty ||
                            s.query.toLowerCase().contains(q) ||
                            s.tool.toLowerCase().contains(q)),
                  )
                  .toList();
              final content = list.isEmpty
                  ? RecordsEmptyState(
                      title: _onlyGaps && q.isEmpty
                          ? l10n.t('hist.noGaps')
                          : l10n.t('records.noMatch'),
                      description: l10n.t('records.noMatchHint'),
                      icon: Icons.manage_search_outlined,
                    )
                  : MasterDetail(
                      master: ListView.builder(
                        itemCount: list.length,
                        itemBuilder: (context, i) {
                          final s = list[i];
                          final gap = s.hits == 0;
                          return ListTile(
                            selected: _selected?.id.value == s.id.value,
                            leading: _ToolBadge(s.tool),
                            title: Text(
                              s.query.isEmpty ? '(empty query)' : s.query,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '${s.tool} · ${gap ? l10n.t('hist.gap') : '${s.hits} ${l10n.t('hist.hits')}'}'
                              '${s.latencyMs == null ? '' : ' · ${s.latencyMs}ms'} · ${fmtDateTime(s.createdAt)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: gap ? OracleBrand.warning : null,
                              ),
                            ),
                            onTap: () => setState(() => _selected = s),
                          );
                        },
                      ),
                      detail: _selected == null
                          ? Center(child: Text(l10n.t('hist.selectOne')))
                          : _SearchDetail(search: _selected!),
                    );
              return Column(
                children: [
                  RecordsToolbar(
                    title: l10n.t('nav.searchHistory'),
                    description: l10n.t('hist.intro'),
                    searchController: _query,
                    onSearchChanged: (_) => setState(() {}),
                    onRefresh: _reload,
                    resultCount: list.length,
                    filters: [
                      FilterChip(
                        selected: _onlyGaps,
                        label: Text(l10n.t('hist.onlyGaps')),
                        avatar: const Icon(
                          Icons.report_gmailerrorred_outlined,
                          size: 16,
                        ),
                        onSelected: (v) => setState(() => _onlyGaps = v),
                      ),
                      ChoiceChip(
                        label: Text(l10n.t('records.all')),
                        selected: _tool == 'all',
                        onSelected: (_) => setState(() => _tool = 'all'),
                      ),
                      for (final tool in tools)
                        ChoiceChip(
                          avatar: Icon(_toolIcon(tool), size: 16),
                          label: Text(tool),
                          selected: _tool == tool,
                          onSelected: (_) => setState(() => _tool = tool),
                        ),
                    ],
                  ),
                  Expanded(child: content),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

IconData _toolIcon(String tool) => switch (tool) {
  'memory' => Icons.psychology_outlined,
  'rule' => Icons.rule_outlined,
  'skill' => Icons.school_outlined,
  'architecture' => Icons.account_tree_outlined,
  _ => Icons.search,
};

class _ToolBadge extends StatelessWidget {
  final String tool;
  const _ToolBadge(this.tool);
  @override
  Widget build(BuildContext context) =>
      CircleAvatar(radius: 16, child: Icon(_toolIcon(tool), size: 16));
}

class _SearchDetail extends StatelessWidget {
  final AgentSearchEntity search;
  const _SearchDetail({required this.search});

  @override
  Widget build(BuildContext context) {
    final scope = search.scope;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          search.query.isEmpty ? '(empty query)' : search.query,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            MetaChip(search.tool, icon: _toolIcon(search.tool)),
            MetaChip(
              '${search.hits} ${l10n.t('hist.hits')}',
              icon: search.hits == 0
                  ? Icons.report_gmailerrorred_outlined
                  : Icons.check_circle_outline,
            ),
            if (search.latencyMs != null)
              MetaChip('${search.latencyMs} ms', icon: Icons.timer_outlined),
            MetaChip(fmtDateTime(search.createdAt), icon: Icons.schedule),
            if (scope['moduleId'] != null)
              MetaChip('module', icon: Icons.widgets_outlined),
            if (scope['projectId'] != null)
              MetaChip('project', icon: Icons.folder_outlined),
            if (scope['organizationId'] != null)
              MetaChip('org', icon: Icons.apartment_outlined),
          ],
        ),
        if (search.filters.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            l10n.t('hist.filters'),
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: OracleBrand.gray100,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${search.filters}',
            style: const TextStyle(fontSize: 12, color: OracleBrand.gray400),
          ),
        ],
        const Divider(height: 32),
        Text(
          '${l10n.t('hist.results')} (${search.results.length})',
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            color: OracleBrand.gray100,
          ),
        ),
        const SizedBox(height: 8),
        if (search.results.isEmpty)
          Text(
            l10n.t('hist.gapNote'),
            style: const TextStyle(
              fontSize: 13,
              color: OracleBrand.warning,
              height: 1.4,
            ),
          )
        else
          for (final r in search.results)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              clipBehavior: Clip.antiAlias,
              child: ExpansionTile(
                leading: Icon(_toolIcon(search.tool), size: 19),
                title: Text(
                  '${r['title'] ?? r['name'] ?? l10n.t('hist.recordUnavailable')}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  '${r['subtitle'] ?? r['id']}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: OracleBrand.gray400,
                  ),
                ),
                trailing: r['score'] == null
                    ? null
                    : Text(
                        (r['score'] as num).toStringAsFixed(3),
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: OracleBrand.gray400,
                        ),
                      ),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if ('${r['content'] ?? ''}'.trim().isNotEmpty)
                    MarkdownView('${r['content']}')
                  else
                    Text(
                      l10n.t('hist.recordUnavailableHint'),
                      style: const TextStyle(color: OracleBrand.gray500),
                    ),
                  const SizedBox(height: 10),
                  SelectableText(
                    'ID: ${r['id']}',
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontFamily: 'monospace',
                      color: OracleBrand.gray500,
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}
