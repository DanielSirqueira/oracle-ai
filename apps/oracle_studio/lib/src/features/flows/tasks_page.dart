import 'package:flutter/material.dart';
import 'package:oracle_core/oracle_core.dart';
import 'package:oracle_memory/oracle_memory.dart';

import '../../core/brand.dart';
import '../../core/daemon_host.dart';
import '../../core/fmt.dart';
import '../../core/l10n.dart';
import '../../widgets/async_view.dart';
import '../../widgets/editor_dialog.dart';
import '../../widgets/records_toolbar.dart';
import 'flow_labels.dart';

/// Loop Engineering — the backlog. File a development task, then run it with a
/// process: that enqueues a flow run (status queued) which the Flow Runner picks
/// up and drives step by step.
class TasksPage extends StatefulWidget {
  final ValueNotifier<ProjectEntity?> project;
  final DaemonHost daemon;
  const TasksPage({super.key, required this.project, required this.daemon});

  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
  Future<List<TaskEntity>>? _future;
  final _query = TextEditingController();
  final Set<String> _startingTaskIds = <String>{};
  String _status = 'all';

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
          .get<ListTasksUsecase>()(
            organizationId: project.organizationId,
            projectId: project.id,
            limit: 100,
          )
          .then((r) => r.getOrThrow());
    });
  }

  Future<void> _newTask() async {
    final project = widget.project.value;
    if (project == null) return;
    final title = TextEditingController();
    final desc = TextEditingController();
    final priority = TextEditingController(text: '50');

    final saved = await showEditorDialog(
      context,
      title: l10n.t('tasks.newTitle'),
      fields: (context, setState) => [
        FieldRow(l10n.t('tasks.fTitle'), title),
        FieldRow(l10n.t('tasks.fDesc'), desc, maxLines: 5),
        FieldRow(
          l10n.t('tasks.fPriority'),
          priority,
          description: l10n.t('tasks.fPriorityDesc'),
        ),
      ],
      onSave: () async {
        if (title.text.trim().isEmpty) return l10n.t('tasks.titleRequired');
        final task = TaskEntity(
          id: const IdVO.empty(),
          organizationId: project.organizationId,
          projectId: project.id,
          title: TextVO(title.text.trim()),
          description: desc.text.trim(),
          priority: int.tryParse(priority.text.trim())?.clamp(0, 100) ?? 50,
          source: 'human',
          createdBy: 'oracle-studio',
        );
        final result = await injector.get<CreateTaskUsecase>()(task);
        return result.fold((_) => null, (f) => f.errorMessage);
      },
    );
    if (saved == true && mounted) {
      showSnack(context, l10n.t('tasks.created'));
      _reload();
    }
  }

  Future<void> _run(TaskEntity task) async {
    final taskId = task.id.value;
    if (_startingTaskIds.contains(taskId)) return;
    if (task.status == TaskStatus.done || task.status == TaskStatus.cancelled) {
      showSnack(context, l10n.t('tasks.terminalNoRerun'));
      return;
    }
    if (task.status == TaskStatus.running) {
      showSnack(context, l10n.t('tasks.alreadyRunning'));
      return;
    }
    final project = widget.project.value;
    if (project == null) return;
    setState(() => _startingTaskIds.add(taskId));
    try {
      final flows = await injector
          .get<ListFlowsUsecase>()(
            organizationId: project.organizationId,
            projectId: project.id,
            limit: 100,
          )
          .then((r) => r.getOrDefault(const []));
      if (!mounted) return;
      if (flows.isEmpty) {
        showSnack(context, l10n.t('tasks.noFlows'));
        return;
      }
      final flow = await showDialog<FlowEntity>(
        context: context,
        builder: (context) => SimpleDialog(
          title: Text(l10n.t('tasks.pickFlow')),
          children: [
            for (final f in flows)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, f),
                child: ListTile(
                  leading: const Icon(Icons.account_tree_outlined),
                  title: Text(f.name.value),
                  subtitle: Text(
                    '${f.key} · v${f.versionNo} · ${agentLabel(f.orchestratorAgent)}',
                  ),
                ),
              ),
          ],
        ),
      );
      if (flow == null || !mounted) return;
      final result = await injector.get<StartFlowRunUsecase>()(
        taskId: task.id,
        flowId: flow.id,
        organizationId: project.organizationId,
        projectId: project.id,
        startedBy: 'oracle-studio',
      );
      if (!mounted) return;
      result.fold(
        (run) {
          // Warn immediately when nothing will pick the run up — the #1 "nothing
          // happens" cause is the Flow Runner being off (it is opt-in).
          showSnack(
            context,
            widget.daemon.workerRunning
                ? '${l10n.t('tasks.enqueued')} — ${runStatusLabel(run.status)}'
                : l10n.t('tasks.workerOff'),
          );
          _reload();
        },
        (f) => showSnack(
          context,
          '${l10n.t('common.failure')}: ${f.errorMessage}',
        ),
      );
    } finally {
      if (mounted) setState(() => _startingTaskIds.remove(taskId));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_future == null) {
      return Center(child: Text(l10n.t('common.selectProject')));
    }
    return AsyncView<List<TaskEntity>>(
      future: _future!,
      onRetry: _reload,
      builder: (context, tasks) {
        final q = _query.text.trim().toLowerCase();
        final filtered = tasks
            .where(
              (t) =>
                  (_status == 'all' || t.status.code == _status) &&
                  (q.isEmpty ||
                      t.title.value.toLowerCase().contains(q) ||
                      t.description.toLowerCase().contains(q) ||
                      t.source.toLowerCase().contains(q) ||
                      t.createdBy.toLowerCase().contains(q)),
            )
            .toList();
        return Column(
          children: [
            RecordsToolbar(
              title: l10n.t('nav.tasks'),
              description: l10n.t('nav.tasksHint'),
              searchController: _query,
              onSearchChanged: (_) => setState(() {}),
              onRefresh: _reload,
              resultCount: filtered.length,
              filters: [
                ChoiceChip(
                  label: Text(l10n.t('records.all')),
                  selected: _status == 'all',
                  onSelected: (_) => setState(() => _status = 'all'),
                ),
                for (final status in TaskStatus.values)
                  ChoiceChip(
                    label: Text(taskStatusLabel(status)),
                    selected: _status == status.code,
                    onSelected: (_) => setState(() => _status = status.code),
                  ),
              ],
              actions: [
                FilledButton.icon(
                  onPressed: _newTask,
                  icon: const Icon(Icons.add),
                  label: Text(l10n.t('tasks.new')),
                ),
              ],
            ),
            Expanded(
              child: filtered.isEmpty
                  ? RecordsEmptyState(
                      title: tasks.isEmpty
                          ? l10n.t('tasks.empty')
                          : l10n.t('records.noMatch'),
                      description: tasks.isEmpty
                          ? null
                          : l10n.t('records.noMatchHint'),
                      icon: Icons.task_alt_outlined,
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      itemCount: filtered.length,
                      itemBuilder: (context, i) {
                        final t = filtered[i];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          StatusBadge(
                                            taskStatusLabel(t.status),
                                            color: taskStatusColor(t.status),
                                          ),
                                          const SizedBox(width: 8),
                                          MetaChip(
                                            'P${t.priority}',
                                            icon: Icons.flag_outlined,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            fmtDateTime(
                                              t.updatedAt ?? t.createdAt,
                                            ),
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: OracleBrand.gray500,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        t.title.value,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      if (t.description.trim().isNotEmpty) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          t.description,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: OracleBrand.gray400,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                Tooltip(
                                  message:
                                      t.status == TaskStatus.done ||
                                          t.status == TaskStatus.cancelled
                                      ? l10n.t('tasks.terminalNoRerun')
                                      : t.status == TaskStatus.running
                                      ? l10n.t('tasks.alreadyRunning')
                                      : l10n.t('tasks.run'),
                                  child: FilledButton.tonalIcon(
                                    onPressed:
                                        t.status == TaskStatus.running ||
                                            t.status == TaskStatus.done ||
                                            t.status == TaskStatus.cancelled ||
                                            _startingTaskIds.contains(
                                              t.id.value,
                                            )
                                        ? null
                                        : () => _run(t),
                                    icon: _startingTaskIds.contains(t.id.value)
                                        ? const SizedBox.square(
                                            dimension: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : Icon(
                                            t.status == TaskStatus.done
                                                ? Icons.check_circle_outline
                                                : Icons.play_arrow,
                                            size: 18,
                                          ),
                                    label: Text(
                                      t.status == TaskStatus.done
                                          ? l10n.t('tasks.completed')
                                          : l10n.t('tasks.run'),
                                    ),
                                  ),
                                ),
                              ],
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
