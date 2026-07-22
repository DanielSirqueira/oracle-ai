import 'package:flutter/material.dart';
import 'package:oracle_core/oracle_core.dart';
import 'package:oracle_memory/oracle_memory.dart';

import '../../core/l10n.dart';
import '../../widgets/async_view.dart';
import '../../widgets/markdown_view.dart';
import '../../widgets/records_toolbar.dart';

class _GlobalResults {
  final List<MemorySearchResult> memories;
  final List<RuleSearchResult> rules;
  final List<SkillSearchResult> skills;
  final List<ArchitectureSearchResult> sections;
  const _GlobalResults({
    required this.memories,
    required this.rules,
    required this.skills,
    required this.sections,
  });
  bool get isEmpty =>
      memories.isEmpty && rules.isEmpty && skills.isEmpty && sections.isEmpty;
}

/// One query across the whole memory bank: memories, rules, skills and
/// architecture sections searched in parallel with the same hybrid (vector +
/// full-text) engines the agents use.
class SearchPage extends StatefulWidget {
  final ValueNotifier<ProjectEntity?> project;
  const SearchPage({super.key, required this.project});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _query = TextEditingController();
  Future<_GlobalResults>? _future;
  String _kind = 'all';

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _search() {
    final q = _query.text.trim();
    if (q.isEmpty) return;
    final pid = widget.project.value?.id;
    setState(() {
      _future = () async {
        final results = await Future.wait([
          injector
              .get<SearchMemoriesUsecase>()(
                MemorySearchFilter(query: q, projectId: pid, limit: 10),
              )
              .then((r) => r.getOrDefault(const [])),
          injector
              .get<SearchRulesUsecase>()(
                RuleSearchFilter(query: q, projectId: pid, limit: 10),
              )
              .then((r) => r.getOrDefault(const [])),
          injector
              .get<SearchSkillsUsecase>()(
                SkillSearchFilter(query: q, projectId: pid, limit: 10),
              )
              .then((r) => r.getOrDefault(const [])),
          injector
              .get<SearchArchitectureUsecase>()(
                ArchitectureSearchFilter(query: q, projectId: pid, limit: 10),
              )
              .then((r) => r.getOrDefault(const [])),
        ]);
        return _GlobalResults(
          memories: results[0] as List<MemorySearchResult>,
          rules: results[1] as List<RuleSearchResult>,
          skills: results[2] as List<SkillSearchResult>,
          sections: results[3] as List<ArchitectureSearchResult>,
        );
      }();
    });
  }

  void _showContent(BuildContext context, String title, String body) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 640,
          child: SingleChildScrollView(child: MarkdownView(body)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.t('common.close')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        RecordsToolbar(
          title: l10n.t('nav.search'),
          description: l10n.t('nav.searchHint'),
          searchController: _query,
          searchHint: l10n.t('search.hint'),
          onSearchSubmitted: (_) => _search(),
          onRefresh: _search,
          filters: [
            for (final kind in const [
              'all',
              'memories',
              'rules',
              'skills',
              'sections',
            ])
              ChoiceChip(
                label: Text(
                  kind == 'all'
                      ? l10n.t('records.all')
                      : l10n.t('search.$kind'),
                ),
                selected: _kind == kind,
                onSelected: (_) => setState(() => _kind = kind),
              ),
          ],
          actions: [
            FilledButton.icon(
              onPressed: _search,
              icon: const Icon(Icons.search),
              label: Text(l10n.t('nav.search')),
            ),
          ],
        ),
        Expanded(
          child: _future == null
              ? Center(child: Text(l10n.t('search.prompt')))
              : AsyncView<_GlobalResults>(
                  future: _future!,
                  builder: (context, data) => data.isEmpty
                      ? Center(child: Text(l10n.t('search.empty')))
                      : ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            if ((_kind == 'all' || _kind == 'memories') &&
                                data.memories.isNotEmpty) ...[
                              _SectionHeader(
                                l10n.t('search.memories'),
                                Icons.psychology_outlined,
                                data.memories.length,
                              ),
                              for (final h in data.memories)
                                _HitTile(
                                  icon: Icons.psychology_outlined,
                                  title: h.memory.title.value,
                                  subtitle:
                                      '${h.memory.kind.code} · ${h.memory.tier.code} · score ${h.score.toStringAsFixed(3)}',
                                  onTap: () => _showContent(
                                    context,
                                    h.memory.title.value,
                                    h.memory.body.value,
                                  ),
                                ),
                              const SizedBox(height: 16),
                            ],
                            if ((_kind == 'all' || _kind == 'rules') &&
                                data.rules.isNotEmpty) ...[
                              _SectionHeader(
                                l10n.t('search.rules'),
                                Icons.rule_outlined,
                                data.rules.length,
                              ),
                              for (final h in data.rules)
                                _HitTile(
                                  icon: Icons.rule_outlined,
                                  title: h.rule.title.value,
                                  subtitle:
                                      '${h.rule.key} · ${h.rule.scope} · score ${h.score.toStringAsFixed(3)}',
                                  onTap: () => _showContent(
                                    context,
                                    h.rule.title.value,
                                    h.rule.content.value,
                                  ),
                                ),
                              const SizedBox(height: 16),
                            ],
                            if ((_kind == 'all' || _kind == 'skills') &&
                                data.skills.isNotEmpty) ...[
                              _SectionHeader(
                                l10n.t('search.skills'),
                                Icons.school_outlined,
                                data.skills.length,
                              ),
                              for (final h in data.skills)
                                _HitTile(
                                  icon: Icons.school_outlined,
                                  title: h.skill.name.value,
                                  subtitle:
                                      '${h.skill.key} · score ${h.score.toStringAsFixed(3)}',
                                  onTap: () => _showContent(
                                    context,
                                    h.skill.name.value,
                                    '${h.skill.description.value}\n\n${h.skill.content.value}',
                                  ),
                                ),
                              const SizedBox(height: 16),
                            ],
                            if ((_kind == 'all' || _kind == 'sections') &&
                                data.sections.isNotEmpty) ...[
                              _SectionHeader(
                                l10n.t('search.sections'),
                                Icons.account_tree_outlined,
                                data.sections.length,
                              ),
                              for (final h in data.sections)
                                _HitTile(
                                  icon: Icons.account_tree_outlined,
                                  title: h.architecture.area,
                                  subtitle:
                                      'score ${h.score.toStringAsFixed(3)}',
                                  onTap: () => _showContent(
                                    context,
                                    h.architecture.area,
                                    h.architecture.content.value,
                                  ),
                                ),
                            ],
                          ],
                        ),
                ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  final IconData icon;
  final int count;
  const _SectionHeader(this.label, this.icon, this.count);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Text(
            '$label ($count)',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    );
  }
}

class _HitTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _HitTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: ListTile(
        leading: Icon(icon, size: 20),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
        onTap: onTap,
      ),
    );
  }
}
