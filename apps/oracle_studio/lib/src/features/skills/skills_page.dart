import 'package:flutter/material.dart';
import 'package:oracle_core/oracle_core.dart';
import 'package:oracle_memory/oracle_memory.dart';
import 'package:oracle_server/oracle_server.dart';

import '../../core/fmt.dart';
import '../../core/l10n.dart';
import '../../widgets/async_view.dart';
import '../../widgets/editor_dialog.dart';
import '../../widgets/markdown_view.dart';
import '../../widgets/records_toolbar.dart';

/// The central skill library: browse, create, edit (same key = supersede),
/// retire, and materialize to disk (sync) for native agent discovery.
class SkillsPage extends StatefulWidget {
  final ValueNotifier<ProjectEntity?> project;
  const SkillsPage({super.key, required this.project});

  @override
  State<SkillsPage> createState() => _SkillsPageState();
}

class _SkillsPageState extends State<SkillsPage> {
  SkillEntity? _selectedSkill;
  Future<List<SkillEntity>>? _future;
  bool _syncing = false;
  final _query = TextEditingController();
  String _scope = 'all';

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
    setState(() {
      _selectedSkill = null;
      _future = injector
          .get<ListSkillsUsecase>()(
            projectId: widget.project.value?.id,
            limit: 500,
          )
          .then((r) => r.getOrThrow());
    });
  }

  Future<void> _editSkill({SkillEntity? original}) async {
    final project = widget.project.value;
    final key = TextEditingController(text: original?.key ?? '');
    final name = TextEditingController(text: original?.name.value ?? '');
    final description = TextEditingController(
      text: original?.description.value ?? '',
    );
    final content = TextEditingController(text: original?.content.value ?? '');
    final tags = TextEditingController(text: original?.tags.join(', ') ?? '');
    // Scope: keep the original owner on edit; new skills default to global.
    var scopeToProject = original == null ? false : original.projectId != null;

    final saved = await showEditorDialog(
      context,
      width: 760,
      title: original == null
          ? l10n.t('skill.newTitle')
          : l10n.t('skill.editTitle'),
      fields: (context, setState) => [
        FieldRow(l10n.t('skill.fieldKey'), key, enabled: original == null),
        FieldRow(l10n.t('skill.fieldName'), name),
        FieldRow(l10n.t('skill.fieldDesc'), description, maxLines: 3),
        FieldRow(l10n.t('skill.fieldContent'), content, maxLines: 14),
        FieldRow(l10n.t('common.tags'), tags),
        if (original == null)
          DropdownButtonFormField<bool>(
            initialValue: scopeToProject,
            decoration: InputDecoration(
              labelText: l10n.t('skill.scope'),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            items: [
              DropdownMenuItem(
                value: false,
                child: Text(l10n.t('skill.scopeGlobal')),
              ),
              DropdownMenuItem(
                value: true,
                enabled: project != null,
                child: Text(
                  project == null
                      ? l10n.t('skill.scopeSelectProject')
                      : '${l10n.t('skill.scopeProject')} (${project.name.value})',
                ),
              ),
            ],
            onChanged: (v) => scopeToProject = v ?? scopeToProject,
          ),
      ],
      onSave: () async {
        final result = await injector.get<SaveSkillUsecase>()(
          SkillEntity(
            id: const IdVO.empty(),
            projectId: original != null
                ? original.projectId
                : (scopeToProject ? project?.id : null),
            organizationId: original?.organizationId,
            key: key.text.trim(),
            name: TextVO(name.text),
            description: TextVO(description.text),
            content: TextVO(content.text),
            tags: parseTags(tags.text),
          ),
        );
        return result.fold((_) => null, (f) => f.errorMessage);
      },
    );
    if (saved == true && mounted) {
      showSnack(
        context,
        original == null ? l10n.t('skill.created') : l10n.t('skill.updated'),
      );
      _reload();
    }
  }

  Future<void> _retireSkill(SkillEntity skill, {required bool hard}) async {
    final ok = await confirmAction(
      context,
      title: hard ? l10n.t('skill.deleteQ') : l10n.t('skill.retireQ'),
      message:
          '"${skill.name.value}" '
          '${hard ? l10n.t('skill.deleteMsg') : l10n.t('skill.retireMsg')}',
      okLabel: hard ? l10n.t('common.delete') : l10n.t('common.retire'),
      destructive: true,
    );
    if (!ok) return;
    final result = await injector.get<RetireSkillUsecase>()(
      skill.id,
      reason: 'via Oracle Studio',
      hard: hard,
    );
    if (!mounted) return;
    result.fold(
      (_) {
        showSnack(
          context,
          hard ? l10n.t('skill.deleted') : l10n.t('skill.retired'),
        );
        _reload();
      },
      (f) =>
          showSnack(context, '${l10n.t('common.failure')}: ${f.errorMessage}'),
    );
  }

  /// Projects the library onto disk for native discovery (~/.claude/skills) —
  /// same service the CLI uses, safe by the managed-by marker.
  Future<void> _syncToDisk() async {
    setState(() => _syncing = true);
    try {
      final report = await const SkillSyncService().sync();
      if (mounted) {
        showSnack(
          context,
          '${l10n.t('skill.synced')}: ${report.synced} skill(s) → ${report.dir} '
          '(${report.pruned} ${l10n.t('skill.pruned')}).',
        );
      }
    } catch (e) {
      if (mounted) showSnack(context, '${l10n.t('skill.syncFail')}: $e');
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AsyncView<List<SkillEntity>>(
      future: _future ?? Future.value(const []),
      onRetry: _reload,
      builder: (context, skills) {
        final q = _query.text.trim().toLowerCase();
        final filtered = skills.where((s) {
          final scope = s.projectId != null
              ? 'project'
              : (s.organizationId != null ? 'organization' : 'global');
          final matchesText =
              q.isEmpty ||
              s.name.value.toLowerCase().contains(q) ||
              s.key.toLowerCase().contains(q) ||
              s.description.value.toLowerCase().contains(q) ||
              s.tags.any((tag) => tag.toLowerCase().contains(q));
          return matchesText && (_scope == 'all' || scope == _scope);
        }).toList();
        return Column(
          children: [
            RecordsToolbar(
              title: l10n.t('nav.skills'),
              description: l10n.t('nav.skillsHint'),
              searchController: _query,
              onSearchChanged: (_) => setState(() {}),
              onRefresh: _reload,
              resultCount: filtered.length,
              filters: [
                for (final value in const [
                  'all',
                  'global',
                  'organization',
                  'project',
                ])
                  ChoiceChip(
                    label: Text(
                      value == 'all'
                          ? l10n.t('records.all')
                          : l10n.t('skill.$value'),
                    ),
                    selected: _scope == value,
                    onSelected: (_) => setState(() => _scope = value),
                  ),
              ],
              actions: [
                OutlinedButton.icon(
                  onPressed: _syncing ? null : _syncToDisk,
                  icon: _syncing
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync),
                  label: Text(
                    _syncing ? l10n.t('skill.syncing') : l10n.t('skill.sync'),
                  ),
                ),
                FilledButton.icon(
                  onPressed: () => _editSkill(),
                  icon: const Icon(Icons.add),
                  label: Text(l10n.t('skill.new')),
                ),
              ],
            ),
            Expanded(
              child: filtered.isEmpty
                  ? RecordsEmptyState(
                      title: l10n.t('records.noMatch'),
                      description: l10n.t('records.noMatchHint'),
                      icon: Icons.school_outlined,
                    )
                  : MasterDetail(
                      master: ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (context, i) {
                          final s = filtered[i];
                          final scope = s.projectId != null
                              ? l10n.t('skill.project')
                              : (s.organizationId != null
                                    ? l10n.t('skill.organization')
                                    : l10n.t('skill.global'));
                          return ListTile(
                            selected: _selectedSkill?.id.value == s.id.value,
                            leading: Icon(
                              s.projectId == null && s.organizationId == null
                                  ? Icons.public
                                  : Icons.folder_outlined,
                              size: 20,
                            ),
                            title: Text(
                              s.name.value,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '${s.key} · $scope',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () => setState(() => _selectedSkill = s),
                          );
                        },
                      ),
                      detail: _selectedSkill == null
                          ? Center(child: Text(l10n.t('skill.selectOne')))
                          : _SkillDetail(
                              skill: _selectedSkill!,
                              onEdit: () =>
                                  _editSkill(original: _selectedSkill),
                              onRetire: (hard) =>
                                  _retireSkill(_selectedSkill!, hard: hard),
                            ),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _SkillDetail extends StatelessWidget {
  final SkillEntity skill;
  final VoidCallback onEdit;
  final void Function(bool hard) onRetire;
  const _SkillDetail({
    required this.skill,
    required this.onEdit,
    required this.onRetire,
  });

  @override
  Widget build(BuildContext context) {
    final isGlobal = skill.projectId == null && skill.organizationId == null;
    final scope = skill.projectId != null
        ? l10n.t('skill.project')
        : (skill.organizationId != null
              ? l10n.t('skill.organization')
              : l10n.t('skill.global'));
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                skill.name.value,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            IconButton(
              tooltip: l10n.t('common.editVersion'),
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
        const SizedBox(height: 8),
        Text(
          skill.description.value,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            MetaChip('key: ${skill.key}', icon: Icons.key),
            MetaChip(
              scope,
              icon: isGlobal ? Icons.public : Icons.folder_outlined,
            ),
            MetaChip(fmtDateTime(skill.createdAt), icon: Icons.schedule),
            for (final t in skill.tags) MetaChip('#$t'),
          ],
        ),
        const Divider(height: 32),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: MarkdownView(skill.content.value),
          ),
        ),
      ],
    );
  }
}
