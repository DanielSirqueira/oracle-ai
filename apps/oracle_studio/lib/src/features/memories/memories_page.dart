import 'package:flutter/material.dart';
import 'package:oracle_core/oracle_core.dart';
import 'package:oracle_memory/oracle_memory.dart';

import '../../core/fmt.dart';
import '../../core/l10n.dart';
import '../../widgets/async_view.dart';
import '../../widgets/editor_dialog.dart';
import '../../widgets/markdown_view.dart';

/// Browse and curate the consolidated memories of the selected project: hybrid
/// search, create, edit (a new version superseding the old — history is kept)
/// and forget (soft with reason, or hard).
class MemoriesPage extends StatefulWidget {
  final ValueNotifier<ProjectEntity?> project;
  const MemoriesPage({super.key, required this.project});

  @override
  State<MemoriesPage> createState() => _MemoriesPageState();
}

class _MemoriesPageState extends State<MemoriesPage> {
  final _query = TextEditingController();
  MemoryEntity? _selectedMemory;
  Future<List<MemoryEntity>>? _future;

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
      _selectedMemory = null;
      final q = _query.text.trim();
      _future = q.isEmpty
          ? injector
              .get<TopMemoriesUsecase>()(project.id, limit: 50)
              .then((r) => r.getOrThrow())
          : injector
              .get<SearchMemoriesUsecase>()(MemorySearchFilter(
                query: q,
                projectId: project.id,
                limit: 50,
              ))
              .then((r) => r.getOrThrow().map((h) => h.memory).toList());
    });
  }

  Future<void> _editMemory({MemoryEntity? original}) async {
    final project = widget.project.value;
    if (project == null) return;
    final title = TextEditingController(text: original?.title.value ?? '');
    final body = TextEditingController(text: original?.body.value ?? '');
    final key = TextEditingController(text: original?.key ?? '');
    final tags = TextEditingController(text: original?.tags.join(', ') ?? '');
    var kind = original?.kind.code ?? 'fact';
    var tier = original?.tier.code ?? 'semantic';
    var importance = original?.importance ?? 0.5;

    final saved = await showEditorDialog(
      context,
      title: original == null ? l10n.t('mem.newTitle') : l10n.t('mem.editTitle'),
      fields: (context, setState) => [
        FieldRow(l10n.t('mem.fieldTitle'), title,
            description: l10n.t('mem.fieldTitleDesc')),
        FieldRow(l10n.t('mem.fieldBody'), body,
            maxLines: 10, description: l10n.t('mem.fieldBodyDesc')),
        FieldRow(l10n.t('mem.fieldKey'), key, description: l10n.t('mem.fieldKeyDesc')),
        FieldRow(l10n.t('common.tags'), tags, description: l10n.t('common.tagsDesc')),
        Row(children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: kind,
              decoration: InputDecoration(
                  labelText: l10n.t('mem.kind'),
                  border: const OutlineInputBorder(),
                  isDense: true),
              items: const [
                DropdownMenuItem(value: 'fact', child: Text('fact')),
                DropdownMenuItem(value: 'decision', child: Text('decision')),
                DropdownMenuItem(value: 'gotcha', child: Text('gotcha')),
                DropdownMenuItem(value: 'rule', child: Text('rule')),
              ],
              onChanged: (v) => kind = v ?? kind,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: tier,
              decoration: InputDecoration(
                  labelText: l10n.t('mem.tier'),
                  border: const OutlineInputBorder(),
                  isDense: true),
              items: const [
                DropdownMenuItem(value: 'semantic', child: Text('semantic')),
                DropdownMenuItem(value: 'episodic', child: Text('episodic')),
                DropdownMenuItem(value: 'procedural', child: Text('procedural')),
              ],
              onChanged: (v) => tier = v ?? tier,
            ),
          ),
        ]),
        const SizedBox(height: 12),
        StatefulBuilder(
          builder: (context, setSlider) => Row(children: [
            Text(l10n.t('mem.importance')),
            Expanded(
              child: Slider(
                value: importance,
                divisions: 20,
                label: importance.toStringAsFixed(2),
                onChanged: (v) => setSlider(() => importance = v),
              ),
            ),
            Text(importance.toStringAsFixed(2)),
          ]),
        ),
      ],
      onSave: () async {
        final k = key.text.trim();
        final result = await injector.get<SaveMemoryUsecase>()(MemoryEntity(
          id: const IdVO.empty(),
          projectId: original?.projectId ?? project.id,
          productId: original?.productId,
          key: k.isEmpty ? null : k,
          // Editing = a NEW version that supersedes the old row (audit trail
          // preserved), exactly like an agent updating a memory.
          supersedes: original?.id,
          tier: MemoryTier.parse(tier),
          kind: MemoryKind.parse(kind),
          title: TextVO(title.text),
          body: TextVO(body.text),
          tags: parseTags(tags.text),
          importance: importance,
        ));
        return result.fold((_) => null, (f) => f.errorMessage);
      },
    );
    if (saved == true && mounted) {
      showSnack(context, original == null ? l10n.t('mem.created') : l10n.t('mem.versionSaved'));
      _reload();
    }
  }

  Future<void> _forgetMemory(MemoryEntity memory, {required bool hard}) async {
    final ok = await confirmAction(
      context,
      title: hard ? l10n.t('mem.deleteQ') : l10n.t('mem.forgetQ'),
      message: '"${memory.title.value}" '
          '${hard ? l10n.t('mem.deleteMsg') : l10n.t('mem.forgetMsg')}',
      okLabel: hard ? l10n.t('common.delete') : l10n.t('mem.forget'),
      destructive: true,
    );
    if (!ok) return;
    final result = await injector
        .get<ForgetMemoryUsecase>()(memory.id, reason: 'via Oracle Studio', hard: hard);
    if (!mounted) return;
    result.fold(
      (_) {
        showSnack(context, hard ? l10n.t('mem.deleted') : l10n.t('mem.forgotten'));
        _reload();
      },
      (f) => showSnack(context, '${l10n.t('common.failure')}: ${f.errorMessage}'),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_future == null) {
      return Center(child: Text(l10n.t('common.selectProject')));
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _query,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: l10n.t('mem.searchHint'),
                    border: const OutlineInputBorder(),
                    isDense: true,
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _query.clear();
                        _reload();
                      },
                    ),
                  ),
                  onSubmitted: (_) => _reload(),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: () => _editMemory(),
                icon: const Icon(Icons.add),
                label: Text(l10n.t('mem.new')),
              ),
            ],
          ),
        ),
        Expanded(
          child: AsyncView<List<MemoryEntity>>(
            future: _future!,
            builder: (context, memories) => MasterDetail(
              master: ListView.builder(
                itemCount: memories.length,
                itemBuilder: (context, i) {
                  final m = memories[i];
                  return ListTile(
                    selected: _selectedMemory?.id.value == m.id.value,
                    leading: _KindBadge(m.kind.code),
                    title: Text(m.title.value, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      '${m.tier.code} · ${l10n.t('mem.importance').toLowerCase()} '
                      '${m.importance.toStringAsFixed(2)}'
                      '${m.key == null ? '' : ' · ${m.key}'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => setState(() => _selectedMemory = m),
                  );
                },
              ),
              detail: _selectedMemory == null
                  ? Center(child: Text(l10n.t('mem.selectOne')))
                  : _MemoryDetail(
                      memory: _selectedMemory!,
                      onEdit: () => _editMemory(original: _selectedMemory),
                      onForget: (hard) => _forgetMemory(_selectedMemory!, hard: hard),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

class _KindBadge extends StatelessWidget {
  final String kind;
  const _KindBadge(this.kind);

  @override
  Widget build(BuildContext context) {
    final icon = switch (kind) {
      'decision' => Icons.alt_route,
      'gotcha' => Icons.warning_amber,
      'rule' => Icons.rule,
      _ => Icons.lightbulb_outline,
    };
    return CircleAvatar(radius: 16, child: Icon(icon, size: 16));
  }
}

class _MemoryDetail extends StatelessWidget {
  final MemoryEntity memory;
  final VoidCallback onEdit;
  final void Function(bool hard) onForget;
  const _MemoryDetail({required this.memory, required this.onEdit, required this.onForget});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(memory.title.value, style: Theme.of(context).textTheme.titleLarge),
            ),
            IconButton(
                tooltip: l10n.t('common.editVersion'),
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined)),
            PopupMenuButton<String>(
              tooltip: l10n.t('mem.forget'),
              icon: const Icon(Icons.delete_outline),
              onSelected: (v) => onForget(v == 'hard'),
              itemBuilder: (context) => [
                PopupMenuItem(value: 'soft', child: Text(l10n.t('mem.forgetSoft'))),
                PopupMenuItem(value: 'hard', child: Text(l10n.t('common.deleteHard'))),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            MetaChip(memory.kind.code, icon: Icons.category_outlined),
            MetaChip(memory.tier.code, icon: Icons.layers_outlined),
            MetaChip(
                '${l10n.t('mem.importance').toLowerCase()} ${memory.importance.toStringAsFixed(2)}'),
            if (memory.key != null) MetaChip('key: ${memory.key}', icon: Icons.key),
            if (memory.embeddingModel != null)
              MetaChip(memory.embeddingModel!, icon: Icons.memory),
            MetaChip(fmtDateTime(memory.createdAt), icon: Icons.schedule),
            for (final t in memory.tags) MetaChip('#$t'),
          ],
        ),
        const Divider(height: 32),
        MarkdownView(memory.body.value),
      ],
    );
  }
}
