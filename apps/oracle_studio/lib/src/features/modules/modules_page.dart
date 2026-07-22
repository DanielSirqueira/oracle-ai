import 'package:flutter/material.dart';
import 'package:oracle_core/oracle_core.dart';
import 'package:oracle_memory/oracle_memory.dart';

import '../../core/brand.dart';
import '../../core/fmt.dart';
import '../../core/l10n.dart';
import '../../core/oracle_connection.dart';
import '../../widgets/async_view.dart';
import '../../widgets/editor_dialog.dart';
import '../../widgets/records_toolbar.dart';

/// Modules of the selected project, plus the tool that fixes the core v2 problem
/// for EXISTING data: reclassify a "fake project" (a submodule an agent
/// registered as its own project) into a module of this project — re-pointing
/// its rules/memories/architecture/skills/sessions and removing the stray project.
class ModulesPage extends StatefulWidget {
  final OracleConnection connection;
  final ValueNotifier<ProjectEntity?> project;
  const ModulesPage({
    super.key,
    required this.connection,
    required this.project,
  });

  @override
  State<ModulesPage> createState() => _ModulesPageState();
}

class _ModulesPageState extends State<ModulesPage> {
  Future<List<ModuleEntity>>? _future;
  bool _busy = false;
  final _query = TextEditingController();

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
      _future = injector
          .get<ListModulesUsecase>()(
            ModuleFilter(projectId: project.id, limit: 200),
          )
          .then((r) => r.getOrThrow());
    });
  }

  Future<void> _reclassify() async {
    final target = widget.project.value;
    final db = widget.connection.database;
    if (target == null || db == null) return;

    // Candidate "fake projects": any other project.
    final projects =
        (await injector.get<ListProjectsUsecase>()(
              const ProjectFilter(limit: 500),
            ))
            .getOrDefault(const [])
            .where((p) => p.id.value != target.id.value)
            .toList();
    if (!mounted) return;
    if (projects.isEmpty) {
      showSnack(context, l10n.t('mod.noOtherProjects'));
      return;
    }

    ProjectEntity? source;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(l10n.t('mod.reclassifyTitle')),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n
                      .t('mod.reclassifyDesc')
                      .replaceFirst('{p}', target.name.value),
                  style: const TextStyle(
                    fontSize: 13,
                    color: OracleBrand.gray400,
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<ProjectEntity>(
                  initialValue: source,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: l10n.t('mod.sourceProject'),
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    for (final p in projects)
                      DropdownMenuItem(
                        value: p,
                        child: Text(
                          '${p.name.value}  ·  ${p.repoPath ?? '—'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (v) => setLocal(() => source = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.t('common.cancel')),
            ),
            FilledButton(
              onPressed: source == null
                  ? null
                  : () => Navigator.pop(context, true),
              child: Text(l10n.t('mod.reclassify')),
            ),
          ],
        ),
      ),
    );
    if (ok != true || source == null) return;

    // 1) Create-or-resolve the module under the target project.
    final path = _pathFor(source!, target);
    final moduleRes = await injector.get<ResolveModuleUsecase>()(
      target.id,
      path,
      name: source!.name.value,
      description: 'Reclassified from project "${source!.name.value}"',
    );
    final module = moduleRes.getOrNull();
    if (module == null) {
      if (mounted) {
        showSnack(
          context,
          '${l10n.t('common.failure')}: ${moduleRes.exceptionOrNull()?.errorMessage}',
        );
      }
      return;
    }

    // 2) Re-point the source project's data, then remove the stray project.
    setState(() => _busy = true);
    final mid = module.id.value;
    final sid = source!.id.value;
    final tid = target.id.value;
    try {
      for (final t in ['rules', 'memories', 'skills']) {
        await db.executeUpdate(
          SqlStatement(
            'UPDATE $t SET module_id = :mid::uuid, project_id = NULL, organization_id = NULL '
            'WHERE project_id = :sid::uuid',
            {'mid': mid, 'sid': sid},
          ),
        );
      }
      await db.executeUpdate(
        SqlStatement(
          'UPDATE architectures SET module_id = :mid::uuid, project_id = NULL WHERE project_id = :sid::uuid',
          {'mid': mid, 'sid': sid},
        ),
      );
      // Keep the captured history under the target project.
      for (final t in ['sessions', 'handoffs']) {
        await db.executeUpdate(
          SqlStatement(
            'UPDATE $t SET project_id = :tid::uuid WHERE project_id = :sid::uuid',
            {'tid': tid, 'sid': sid},
          ),
        );
      }
      await db.executeUpdate(
        SqlStatement('DELETE FROM projects WHERE id = :sid::uuid', {
          'sid': sid,
        }),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showSnack(context, '${l10n.t('common.failure')}: $e');
      }
      return;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    showSnack(context, l10n.t('mod.reclassified'));
    _reload();
  }

  /// A module subpath for the reclassified project — its repo path relative to
  /// the target's, else a slug of its name.
  static String _pathFor(ProjectEntity source, ProjectEntity target) {
    final sp = source.repoPath?.replaceAll(r'\', '/');
    final tp = target.repoPath?.replaceAll(r'\', '/');
    if (sp != null &&
        tp != null &&
        sp.length > tp.length &&
        sp.startsWith(tp)) {
      return sp.substring(tp.length).replaceAll(RegExp(r'^/+|/+$'), '');
    }
    return source.name.value.toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]+'),
      '-',
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.project.value == null) {
      return Center(child: Text(l10n.t('common.selectProject')));
    }
    return AsyncView<List<ModuleEntity>>(
      future: _future!,
      onRetry: _reload,
      builder: (context, modules) {
        final q = _query.text.trim().toLowerCase();
        final filtered = modules
            .where(
              (m) =>
                  q.isEmpty ||
                  m.name.value.toLowerCase().contains(q) ||
                  m.key.toLowerCase().contains(q) ||
                  (m.path ?? '').toLowerCase().contains(q) ||
                  (m.description?.value ?? '').toLowerCase().contains(q),
            )
            .toList();
        return Column(
          children: [
            RecordsToolbar(
              title: l10n.t('nav.modules'),
              description: l10n.t('mod.intro'),
              searchController: _query,
              onSearchChanged: (_) => setState(() {}),
              onRefresh: _reload,
              resultCount: filtered.length,
              actions: [
                FilledButton.icon(
                  onPressed: _busy ? null : _reclassify,
                  icon: const Icon(Icons.merge_type, size: 18),
                  label: Text(l10n.t('mod.reclassify')),
                ),
              ],
            ),
            if (_busy) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: filtered.isEmpty
                  ? RecordsEmptyState(
                      title: q.isEmpty
                          ? l10n.t('mod.empty')
                          : l10n.t('records.noMatch'),
                      description: q.isEmpty
                          ? null
                          : l10n.t('records.noMatchHint'),
                      icon: Icons.widgets_outlined,
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: filtered.length,
                      itemBuilder: (context, i) {
                        final m = filtered[i];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: const Icon(Icons.widgets_outlined),
                            title: Text(m.name.value),
                            subtitle: Text(
                              '${m.path ?? m.key}${m.description == null ? '' : ' · ${m.description!.value}'} '
                              '· ${fmtDateTime(m.createdAt)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}
