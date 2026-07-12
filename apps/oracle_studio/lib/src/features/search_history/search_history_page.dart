import 'package:flutter/material.dart';
import 'package:oracle_core/oracle_core.dart';
import 'package:oracle_memory/oracle_memory.dart';

import '../../core/brand.dart';
import '../../core/fmt.dart';
import '../../core/l10n.dart';
import '../../widgets/async_view.dart';

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
      _selected = null;
      _future = injector
          .get<RecentSearchesUsecase>()(project.id, limit: 300)
          .then((r) => r.getOrThrow());
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_future == null) return Center(child: Text(l10n.t('common.selectProject')));
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(children: [
            Expanded(
              child: Text(l10n.t('hist.intro'),
                  style: const TextStyle(fontSize: 12, color: OracleBrand.gray400)),
            ),
            const SizedBox(width: 12),
            FilterChip(
              selected: _onlyGaps,
              label: Text(l10n.t('hist.onlyGaps')),
              avatar: Icon(Icons.report_gmailerrorred_outlined,
                  size: 16, color: _onlyGaps ? OracleBrand.warning : OracleBrand.gray400),
              onSelected: (v) => setState(() => _onlyGaps = v),
            ),
            const SizedBox(width: 8),
            IconButton(
                tooltip: l10n.t('common.refresh'),
                onPressed: _reload,
                icon: const Icon(Icons.refresh, size: 18)),
          ]),
        ),
        Expanded(
          child: AsyncView<List<AgentSearchEntity>>(
            future: _future!,
            builder: (context, all) {
              final list = _onlyGaps ? all.where((s) => s.hits == 0).toList() : all;
              if (list.isEmpty) {
                return Center(
                    child: Text(_onlyGaps ? l10n.t('hist.noGaps') : l10n.t('hist.empty')));
              }
              return MasterDetail(
                master: ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (context, i) {
                    final s = list[i];
                    final gap = s.hits == 0;
                    return ListTile(
                      selected: _selected?.id.value == s.id.value,
                      leading: _ToolBadge(s.tool),
                      title: Text(s.query.isEmpty ? '(empty query)' : s.query,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        '${s.tool} · ${gap ? l10n.t('hist.gap') : '${s.hits} ${l10n.t('hist.hits')}'}'
                        '${s.latencyMs == null ? '' : ' · ${s.latencyMs}ms'} · ${fmtDateTime(s.createdAt)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: gap ? OracleBrand.warning : null),
                      ),
                      onTap: () => setState(() => _selected = s),
                    );
                  },
                ),
                detail: _selected == null
                    ? Center(child: Text(l10n.t('hist.selectOne')))
                    : _SearchDetail(search: _selected!),
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
        Text(search.query.isEmpty ? '(empty query)' : search.query,
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          MetaChip(search.tool, icon: _toolIcon(search.tool)),
          MetaChip('${search.hits} ${l10n.t('hist.hits')}',
              icon: search.hits == 0 ? Icons.report_gmailerrorred_outlined : Icons.check_circle_outline),
          if (search.latencyMs != null) MetaChip('${search.latencyMs} ms', icon: Icons.timer_outlined),
          MetaChip(fmtDateTime(search.createdAt), icon: Icons.schedule),
          if (scope['moduleId'] != null) MetaChip('module', icon: Icons.widgets_outlined),
          if (scope['projectId'] != null) MetaChip('project', icon: Icons.folder_outlined),
          if (scope['organizationId'] != null) MetaChip('org', icon: Icons.apartment_outlined),
        ]),
        if (search.filters.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(l10n.t('hist.filters'),
              style: const TextStyle(fontWeight: FontWeight.w600, color: OracleBrand.gray100)),
          const SizedBox(height: 4),
          Text('${search.filters}', style: const TextStyle(fontSize: 12, color: OracleBrand.gray400)),
        ],
        const Divider(height: 32),
        Text('${l10n.t('hist.results')} (${search.results.length})',
            style: const TextStyle(fontWeight: FontWeight.w600, color: OracleBrand.gray100)),
        const SizedBox(height: 8),
        if (search.results.isEmpty)
          Text(l10n.t('hist.gapNote'),
              style: const TextStyle(fontSize: 13, color: OracleBrand.warning, height: 1.4))
        else
          for (final r in search.results)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(children: [
                const Icon(Icons.arrow_right, size: 16, color: OracleBrand.gray500),
                Expanded(
                  child: Text('${r['id']}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
                ),
                if (r['score'] != null)
                  Text('score ${(r['score'] as num).toStringAsFixed(3)}',
                      style: const TextStyle(fontSize: 12, color: OracleBrand.gray400)),
              ]),
            ),
      ],
    );
  }
}
