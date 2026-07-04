import 'package:flutter/material.dart';
import 'package:oracle_core/oracle_core.dart';
import 'package:oracle_memory/oracle_memory.dart';
import 'package:oracle_server/oracle_server.dart';

import '../../core/fmt.dart';
import '../../widgets/async_view.dart';
import '../../widgets/editor_dialog.dart';

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
    setState(() {
      _selectedSkill = null;
      _future = injector
          .get<ListSkillsUsecase>()(projectId: widget.project.value?.id, limit: 500)
          .then((r) => r.getOrThrow());
    });
  }

  Future<void> _editSkill({SkillEntity? original}) async {
    final project = widget.project.value;
    final key = TextEditingController(text: original?.key ?? '');
    final name = TextEditingController(text: original?.name.value ?? '');
    final description = TextEditingController(text: original?.description.value ?? '');
    final content = TextEditingController(text: original?.content.value ?? '');
    final tags = TextEditingController(text: original?.tags.join(', ') ?? '');
    // Scope: keep the original owner on edit; new skills default to global.
    var scopeToProject = original == null ? false : original.projectId != null;

    final saved = await showEditorDialog(
      context,
      width: 760,
      title: original == null ? 'Nova skill' : 'Editar skill (nova versão)',
      fields: (context, setState) => [
        FieldRow('Key (slug estável, kebab-case — vira o nome da pasta)', key,
            enabled: original == null),
        FieldRow('Nome', name),
        FieldRow('Descrição (o gatilho do recall: o que faz + quando usar)', description,
            maxLines: 3),
        FieldRow('Conteúdo (markdown, estilo SKILL.md)', content, maxLines: 14),
        FieldRow('Tags (separadas por vírgula)', tags),
        if (original == null)
          DropdownButtonFormField<bool>(
            initialValue: scopeToProject,
            decoration: const InputDecoration(
                labelText: 'Escopo', border: OutlineInputBorder(), isDense: true),
            items: [
              const DropdownMenuItem(
                  value: false, child: Text('Global (todos os projetos e agentes)')),
              DropdownMenuItem(
                value: true,
                enabled: project != null,
                child: Text(project == null
                    ? 'Deste projeto (selecione um projeto)'
                    : 'Deste projeto (${project.name.value})'),
              ),
            ],
            onChanged: (v) => scopeToProject = v ?? scopeToProject,
          ),
      ],
      onSave: () async {
        final result = await injector.get<SaveSkillUsecase>()(SkillEntity(
          id: const IdVO.empty(),
          projectId:
              original != null ? original.projectId : (scopeToProject ? project?.id : null),
          productId: original?.productId,
          key: key.text.trim(),
          name: TextVO(name.text),
          description: TextVO(description.text),
          content: TextVO(content.text),
          tags: parseTags(tags.text),
        ));
        return result.fold((_) => null, (f) => f.errorMessage);
      },
    );
    if (saved == true && mounted) {
      showSnack(context, original == null ? 'Skill criada.' : 'Skill atualizada (nova versão).');
      _reload();
    }
  }

  Future<void> _retireSkill(SkillEntity skill, {required bool hard}) async {
    final ok = await confirmAction(
      context,
      title: hard ? 'Apagar permanentemente?' : 'Aposentar skill?',
      message: hard
          ? 'A skill "${skill.name.value}" será APAGADA para sempre.'
          : 'A skill "${skill.name.value}" sai da biblioteca, mas é mantida para auditoria.',
      okLabel: hard ? 'Apagar' : 'Aposentar',
      destructive: true,
    );
    if (!ok) return;
    final result = await injector
        .get<RetireSkillUsecase>()(skill.id, reason: 'via Oracle Studio', hard: hard);
    if (!mounted) return;
    result.fold(
      (_) {
        showSnack(context, hard ? 'Skill apagada.' : 'Skill aposentada.');
        _reload();
      },
      (f) => showSnack(context, 'Falha: ${f.errorMessage}'),
    );
  }

  /// Projects the library onto disk for native discovery (~/.claude/skills) —
  /// same service the CLI uses, safe by the managed-by marker.
  Future<void> _syncToDisk() async {
    setState(() => _syncing = true);
    try {
      final report = await const SkillSyncService().sync();
      if (mounted) {
        showSnack(context,
            'Sincronizado: ${report.synced} skill(s) → ${report.dir} (${report.pruned} removidas).');
      }
    } catch (e) {
      if (mounted) showSnack(context, 'Falha no sync: $e');
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Text('Biblioteca central de skills',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(width: 12),
              Tooltip(
                message: 'Uma única fonte para todos os agentes (MCP). "Sincronizar" materializa\n'
                    'em ~/.claude/skills para descoberta nativa do Claude Code.',
                child: Icon(Icons.info_outline,
                    size: 18, color: Theme.of(context).colorScheme.outline),
              ),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: _syncing ? null : _syncToDisk,
                icon: _syncing
                    ? const SizedBox(
                        width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.sync),
                label: Text(_syncing ? 'Sincronizando…' : 'Sincronizar p/ disco'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: () => _editSkill(),
                icon: const Icon(Icons.add),
                label: const Text('Nova skill'),
              ),
              const SizedBox(width: 8),
              IconButton(tooltip: 'Atualizar', onPressed: _reload, icon: const Icon(Icons.refresh)),
            ],
          ),
        ),
        Expanded(
          child: AsyncView<List<SkillEntity>>(
            future: _future ?? Future.value(const []),
            builder: (context, skills) => skills.isEmpty
                ? const Center(
                    child: Text(
                        'Nenhuma skill ainda — crie aqui ou deixe os agentes salvarem com oracle_skill_save.'))
                : MasterDetail(
                    master: ListView.builder(
                      itemCount: skills.length,
                      itemBuilder: (context, i) {
                        final s = skills[i];
                        final scope = s.projectId != null
                            ? 'projeto'
                            : (s.productId != null ? 'produto' : 'global');
                        return ListTile(
                          selected: _selectedSkill?.id.value == s.id.value,
                          leading: Icon(
                            scope == 'global' ? Icons.public : Icons.folder_outlined,
                            size: 20,
                          ),
                          title: Text(s.name.value, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text('${s.key} · $scope',
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          onTap: () => setState(() => _selectedSkill = s),
                        );
                      },
                    ),
                    detail: _selectedSkill == null
                        ? const Center(child: Text('Selecione uma skill.'))
                        : _SkillDetail(
                            skill: _selectedSkill!,
                            onEdit: () => _editSkill(original: _selectedSkill),
                            onRetire: (hard) => _retireSkill(_selectedSkill!, hard: hard),
                          ),
                  ),
          ),
        ),
      ],
    );
  }
}

class _SkillDetail extends StatelessWidget {
  final SkillEntity skill;
  final VoidCallback onEdit;
  final void Function(bool hard) onRetire;
  const _SkillDetail({required this.skill, required this.onEdit, required this.onRetire});

  @override
  Widget build(BuildContext context) {
    final scope = skill.projectId != null
        ? 'projeto'
        : (skill.productId != null ? 'produto' : 'global');
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            Expanded(child: Text(skill.name.value, style: Theme.of(context).textTheme.titleLarge)),
            IconButton(tooltip: 'Editar (nova versão)', onPressed: onEdit, icon: const Icon(Icons.edit_outlined)),
            PopupMenuButton<String>(
              tooltip: 'Aposentar',
              icon: const Icon(Icons.delete_outline),
              onSelected: (v) => onRetire(v == 'hard'),
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'soft', child: Text('Aposentar (mantém auditoria)')),
                PopupMenuItem(value: 'hard', child: Text('Apagar permanentemente')),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(skill.description.value, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            MetaChip('key: ${skill.key}', icon: Icons.key),
            MetaChip(scope, icon: scope == 'global' ? Icons.public : Icons.folder_outlined),
            MetaChip(fmtDateTime(skill.createdAt), icon: Icons.schedule),
            for (final t in skill.tags) MetaChip('#$t'),
          ],
        ),
        const Divider(height: 32),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SelectableText(
              skill.content.value,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontFamily: 'monospace', height: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}
