import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:oracle_core/oracle_core.dart';
import 'package:oracle_memory/oracle_memory.dart';

import '../../core/brand.dart';
import '../../core/daemon_host.dart';
import '../../core/fmt.dart';
import '../../core/l10n.dart';
import '../../widgets/async_view.dart';
import '../../widgets/editor_dialog.dart';
import '../../widgets/markdown_view.dart';
import '../../widgets/records_toolbar.dart';
import 'flow_labels.dart';

/// Loop Engineering — the run monitor, CI-style: a PIPELINE strip shows where
/// the run is at a glance; each step is a card grouping its iterations; every
/// iteration opens into structured panes — the PROMPT rendered as formatted
/// markdown, the agent report as fields (not raw JSON), the verification as
/// per-command results, and a technical pane with ids + raw payloads.
class RunsPage extends StatefulWidget {
  final ValueNotifier<ProjectEntity?> project;
  final DaemonHost daemon;
  const RunsPage({super.key, required this.project, required this.daemon});

  @override
  State<RunsPage> createState() => _RunsPageState();
}

class _RunsPageState extends State<RunsPage> {
  List<FlowRunEntity>? _runs;
  String? _error;
  FlowRunEntity? _selected;
  bool _activeOnly = false;
  Timer? _poll;
  final _query = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.project.addListener(_reload);
    _reload();
    _poll = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _refresh(silent: true),
    );
  }

  @override
  void dispose() {
    _poll?.cancel();
    widget.project.removeListener(_reload);
    _query.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() {
      _runs = null;
      _error = null;
    });
    _refresh();
  }

  Future<void> _refresh({bool silent = false}) async {
    final project = widget.project.value;
    if (project == null) return;
    final result = await injector.get<ListFlowRunsUsecase>()(
      projectId: project.id,
      limit: 100,
    );
    if (!mounted) return;
    result.fold(
      (runs) => setState(() {
        _runs = runs;
        _error = null;
        if (_selected != null) {
          for (final r in runs) {
            if (r.id.value == _selected!.id.value) _selected = r;
          }
        }
      }),
      (f) => setState(() {
        if (!silent) _error = f.errorMessage;
      }),
    );
  }

  Future<void> _enableWorker() async {
    widget.daemon.settings.hostFlowWorker = true;
    await widget.daemon.applySettings();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (widget.project.value == null) {
      return Center(child: Text(l10n.t('common.selectProject')));
    }
    return AnimatedBuilder(
      animation: widget.daemon,
      builder: (context, _) => Column(
        children: [
          RecordsToolbar(
            title: l10n.t('nav.runs'),
            description: l10n.t('nav.runsHint'),
            searchController: _query,
            onSearchChanged: (_) => setState(() {}),
            onRefresh: _reload,
            resultCount: _runs
                ?.where((run) => !_activeOnly || !run.status.isTerminal)
                .where(_matchesSearch)
                .length,
            filters: [
              ChoiceChip(
                label: Text(l10n.t('runs.allRuns')),
                selected: !_activeOnly,
                onSelected: (_) => setState(() => _activeOnly = false),
              ),
              ChoiceChip(
                label: Text(l10n.t('runs.activeRuns')),
                selected: _activeOnly,
                onSelected: (_) => setState(() => _activeOnly = true),
              ),
            ],
          ),
          if (!widget.daemon.workerRunning)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: OracleBrand.warning.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: OracleBrand.warning.withValues(alpha: 0.45),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.warning_amber_outlined,
                      size: 18,
                      color: OracleBrand.warning,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        l10n.t('runs.workerOffBody'),
                        style: const TextStyle(fontSize: 12.5),
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton(
                      onPressed: _enableWorker,
                      child: Text(l10n.t('runs.workerEnable')),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (_error != null) {
      return Center(child: Text('${l10n.t('common.loadError')}: $_error'));
    }
    final runs = _runs;
    if (runs == null) return const Center(child: CircularProgressIndicator());
    if (runs.isEmpty) {
      return Center(
        child: Text(
          l10n.t('runs.empty'),
          style: const TextStyle(color: OracleBrand.gray400),
        ),
      );
    }
    final visibleRuns = runs
        .where((run) => !_activeOnly || !run.status.isTerminal)
        .where(_matchesSearch)
        .toList();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 320,
          child: Column(
            children: [
              Expanded(
                child: visibleRuns.isEmpty
                    ? Center(
                        child: Text(
                          l10n.t('runs.noActiveRuns'),
                          style: const TextStyle(color: OracleBrand.gray500),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        itemCount: visibleRuns.length,
                        itemBuilder: (context, i) {
                          final run = visibleRuns[i];
                          return _RunListCard(
                            run: run,
                            selected: _selected?.id.value == run.id.value,
                            onTap: () => setState(() => _selected = run),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: _selected == null
              ? Center(child: Text(l10n.t('runs.selectOne')))
              : _RunDetail(
                  key: ValueKey(_selected!.id.value),
                  run: _selected!,
                  onChanged: () => _refresh(silent: true),
                ),
        ),
      ],
    );
  }

  bool _matchesSearch(FlowRunEntity run) {
    final q = _query.text.trim().toLowerCase();
    if (q.isEmpty) return true;
    return run.id.value.toLowerCase().contains(q) ||
        run.flowId.value.toLowerCase().contains(q) ||
        (run.taskId?.value ?? '').toLowerCase().contains(q) ||
        run.status.code.toLowerCase().contains(q) ||
        (run.branchName ?? '').toLowerCase().contains(q) ||
        run.startedBy.toLowerCase().contains(q) ||
        (run.claimedBy ?? '').toLowerCase().contains(q);
  }
}

class _RunListCard extends StatelessWidget {
  final FlowRunEntity run;
  final bool selected;
  final VoidCallback onTap;
  const _RunListCard({
    required this.run,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = runStatusColor(run.status);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: selected ? color.withValues(alpha: .09) : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: selected ? color : OracleBrand.gray700),
      ),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        leading: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: color.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(runStatusIcon(run.status), size: 17, color: color),
        ),
        title: Text(
          '${l10n.t('runs.run')} ${run.id.value.substring(0, 8)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          fmtDateTime(run.startedAt ?? run.createdAt),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: StatusBadge(runStatusLabel(run.status), color: color),
        onTap: onTap,
      ),
    );
  }
}

// ═══════════════════════════ run detail ═══════════════════════════

enum _RunSection { execution, sessions, data, events }

class _RunDetail extends StatefulWidget {
  final FlowRunEntity run;
  final VoidCallback onChanged;
  const _RunDetail({super.key, required this.run, required this.onChanged});

  @override
  State<_RunDetail> createState() => _RunDetailState();
}

class _RunDetailState extends State<_RunDetail> {
  FlowRunBundle? _bundle;
  String? _error;
  List<FlowStepEntity> _defs = const [];
  Map<String, FlowStepEntity> _defsById = const {};
  List<FlowEdgeEntity> _edges = const [];
  bool _showDone = false;
  _RunSection _section = _RunSection.execution;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 4), (_) {
      final st = _bundle?.run.status;
      if (st == null || !st.isTerminal) _load(silent: true);
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    final result = await injector.get<FlowRunStatusUsecase>()(widget.run.id);
    if (!mounted) return;
    if (result.isError()) {
      if (!silent) {
        setState(() => _error = result.exceptionOrNull()!.errorMessage);
      }
      return;
    }
    final bundle = result.getOrThrow();
    if (_defs.isEmpty) {
      final graph = await injector.get<GetFlowUsecase>()(id: bundle.run.flowId);
      if (graph.isSuccess()) {
        final steps = [...graph.getOrThrow().steps]
          ..sort((a, b) => a.position.compareTo(b.position));
        _defs = steps;
        _defsById = {for (final s in steps) s.id.value: s};
        _edges = graph.getOrThrow().edges;
      }
    }
    if (!mounted) return;
    setState(() {
      _bundle = bundle;
      _error = null;
    });
  }

  Future<void> _gate(bool approved) async {
    if (!approved) {
      final ok = await confirmAction(
        context,
        title: l10n.t('runs.rejectQ'),
        message: l10n.t('runs.rejectMsg'),
        okLabel: l10n.t('runs.reject'),
        destructive: true,
      );
      if (!ok) return;
    }
    final result = await injector.get<DecideGateUsecase>()(
      widget.run.id,
      approved: approved,
    );
    if (!mounted) return;
    result.fold(
      (_) {
        showSnack(
          context,
          approved ? l10n.t('runs.approved') : l10n.t('runs.rejected'),
        );
        _load(silent: true);
        widget.onChanged();
      },
      (f) =>
          showSnack(context, '${l10n.t('common.failure')}: ${f.errorMessage}'),
    );
  }

  Future<void> _control(String action) async {
    final result = await injector.get<ControlFlowRunUsecase>()(
      widget.run.id,
      action,
    );
    if (!mounted) return;
    result.fold(
      (_) {
        showSnack(context, l10n.t('runs.ctl.$action'));
        _load(silent: true);
        widget.onChanged();
      },
      (f) =>
          showSnack(context, '${l10n.t('common.failure')}: ${f.errorMessage}'),
    );
  }

  /// User-forced SKIP of the current step: writes the `_skip` blackboard flag
  /// the runner consumes at the next boundary. When the step routes by
  /// verdict, the user picks WHICH connection to follow.
  Future<void> _skipCurrent() async {
    final run = _bundle?.run;
    final stepId = run?.currentStepId?.value;
    final def = stepId == null ? null : _defsById[stepId];
    if (run == null || def == null) return;

    final verdictEdges = [
      for (final e in _edges)
        if (e.fromStep.value == def.id.value &&
            e.condition == 'verdict' &&
            (e.verdictValue ?? '').trim().isNotEmpty)
          e,
    ];
    final hasFallback = _edges.any(
      (e) =>
          e.fromStep.value == def.id.value &&
          (e.condition == 'success' || e.condition == 'always'),
    );

    String? verdict = verdictEdges.isNotEmpty && !hasFallback
        ? verdictEdges.first.verdictValue
        : null;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDlg) => AlertDialog(
          title: Text('${l10n.t('runs.skipQ')} — ${def.stepKey}'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.t('runs.skipMsg'),
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: OracleBrand.gray400,
                  ),
                ),
                if (verdictEdges.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      l10n.t('runs.skipTo'),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  RadioGroup<String?>(
                    groupValue: verdict,
                    onChanged: (v) => setDlg(() => verdict = v),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (hasFallback)
                          RadioListTile<String?>(
                            dense: true,
                            value: null,
                            title: Text(
                              l10n.t('flowcond.success'),
                              style: const TextStyle(fontSize: 12.5),
                            ),
                          ),
                        for (final e in verdictEdges)
                          RadioListTile<String?>(
                            dense: true,
                            value: e.verdictValue,
                            title: Text(
                              '${e.verdictValue} → '
                              '${_defsById[e.toStep.value]?.stepKey ?? '?'}',
                              style: const TextStyle(fontSize: 12.5),
                            ),
                            subtitle: (e.instruction ?? '').trim().isEmpty
                                ? null
                                : Text(
                                    e.instruction!.trim(),
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: OracleBrand.gray500,
                                    ),
                                  ),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.t('common.cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l10n.t('runs.skip')),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final result = await injector.get<PutContextUsecase>()(
      FlowRunContextEntity(
        runId: run.id,
        key: '_skip',
        value: jsonEncode({'step': def.stepKey, 'verdict': verdict}),
      ),
    );
    if (!mounted) return;
    result.fold(
      (_) {
        showSnack(context, l10n.t('runs.skipQueued'));
        _load(silent: true);
      },
      (f) =>
          showSnack(context, '${l10n.t('common.failure')}: ${f.errorMessage}'),
    );
  }

  /// The latest iteration status of a step definition, or null (not run yet).
  FlowRunStepStatus? _stepStatus(String stepId) {
    FlowRunStepEntity? latest;
    for (final s in _bundle!.steps) {
      if (s.stepId.value != stepId) continue;
      if (latest == null || s.iteration > latest.iteration) latest = s;
    }
    return latest?.status;
  }

  /// Edge ids that the runner actually selected. New runs carry explicit
  /// `route` events. For older runs, infer conservatively from visited targets,
  /// source outcome and recorded decision verdicts so an untaken success edge
  /// is never painted red merely because its source later failed.
  Set<String> _traversedEdgeIds(
    FlowRunBundle bundle,
    Map<String, FlowRunStepStatus?> statuses,
  ) {
    final result = <String>{};
    final verdictByStep = <String, String>{};
    for (final event in bundle.events) {
      try {
        final payload = jsonDecode(event.payload);
        if (payload is! Map) continue;
        if (event.kind == 'route') {
          final edgeId = '${payload['edgeId'] ?? ''}'.trim();
          if (edgeId.isNotEmpty) result.add(edgeId);
        } else if (event.kind == 'decision') {
          final step = '${payload['step'] ?? ''}'.trim();
          final verdict = '${payload['verdict'] ?? ''}'.trim();
          if (step.isNotEmpty && verdict.isNotEmpty) {
            verdictByStep[step] = verdict;
          }
        }
      } catch (_) {
        // A malformed historical event must not break the monitor.
      }
    }
    final keyById = {for (final step in _defs) step.id.value: step.stepKey};
    for (final edge in _edges) {
      if (result.contains(edge.id.value) ||
          statuses[edge.toStep.value] == null) {
        continue;
      }
      final sourceStatus = statuses[edge.fromStep.value];
      if (sourceStatus == null) continue;
      final verdict = verdictByStep[keyById[edge.fromStep.value]];
      final matches = verdict != null
          ? edge.condition == 'verdict' &&
                (edge.verdictValue ?? '').trim().toLowerCase() ==
                    verdict.trim().toLowerCase()
          : sourceStatus == FlowRunStepStatus.failed ||
                sourceStatus == FlowRunStepStatus.abandoned
          ? edge.condition == 'failure' || edge.condition == 'always'
          : sourceStatus == FlowRunStepStatus.passed ||
                sourceStatus == FlowRunStepStatus.skipped
          ? edge.condition == 'success' || edge.condition == 'always'
          : false;
      if (matches) result.add(edge.id.value);
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(child: Text('${l10n.t('common.loadError')}: $_error'));
    }
    final bundle = _bundle;
    if (bundle == null) return const Center(child: CircularProgressIndicator());
    final run = bundle.run;
    final terminal = run.status.isTerminal;

    // Group iterations per step, ordered by the flow's positions.
    final byStep = <String, List<FlowRunStepEntity>>{};
    for (final s in bundle.steps) {
      (byStep[s.stepId.value] ??= []).add(s);
    }
    for (final list in byStep.values) {
      list.sort((a, b) => a.iteration.compareTo(b.iteration));
    }
    final orderedStepIds = <String>[
      for (final d in _defs)
        if (byStep.containsKey(d.id.value)) d.id.value,
      for (final id in byStep.keys)
        if (!_defsById.containsKey(id)) id,
    ];
    final statusById = {
      for (final definition in _defs)
        definition.id.value: _stepStatus(definition.id.value),
    };
    final traversedEdgeIds = _traversedEdgeIds(bundle, statusById);
    final displayedRunTokens = byStep.values.fold<int>(
      0,
      (total, iterations) =>
          total +
          _displayTokensByIteration(iterations).values.fold(0, (a, b) => a + b),
    );

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // ── header ──
        Row(
          children: [
            Expanded(
              child: Text(
                '${l10n.t('runs.run')} ${run.id.value.substring(0, 8)}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            StatusBadge(
              runStatusLabel(run.status),
              color: runStatusColor(run.status),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // ── pipeline strip: the whole flow at a glance ──
        if (_defs.isNotEmpty) ...[
          _RunGraph(
            definitions: _defs,
            edges: _edges,
            statuses: statusById,
            currentStepId: terminal ? null : run.currentStepId?.value,
            traversedEdgeIds: traversedEdgeIds,
          ),
          const SizedBox(height: 10),
          _RunProgressSummary(
            definitions: _defs,
            statuses: statusById,
            currentStepId: terminal ? null : run.currentStepId?.value,
          ),
          const SizedBox(height: 14),
        ],
        // ── summary ──
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (run.branchName != null)
              MetaChip(run.branchName!, icon: Icons.merge_type),
            MetaChip(
              '$displayedRunTokens ${l10n.t('runs.tokens')}',
              icon: Icons.toll_outlined,
            ),
            MetaChip(
              fmtDateTime(run.startedAt ?? run.createdAt),
              icon: Icons.schedule,
            ),
            if (run.endedAt != null)
              MetaChip(
                _fmtDuration(run.startedAt, run.endedAt) ?? '',
                icon: Icons.timer_outlined,
              ),
          ],
        ),
        // ── workspace (the worktree where the agents are working) ──
        if (run.worktreePath != null) ...[
          const SizedBox(height: 8),
          Tooltip(
            message: l10n.t('runs.worktreeHint'),
            child: InkWell(
              onTap: () =>
                  Clipboard.setData(ClipboardData(text: run.worktreePath!)),
              borderRadius: BorderRadius.circular(6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.folder_open_outlined,
                    size: 14,
                    color: OracleBrand.gray400,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      '${l10n.t('runs.worktree')}: ${run.worktreePath}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        color: OracleBrand.gray400,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.copy, size: 12, color: OracleBrand.gray500),
                ],
              ),
            ),
          ),
        ],
        if (run.error != null && run.error!.trim().isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            run.error!,
            style: const TextStyle(fontSize: 12, color: OracleBrand.error),
          ),
        ],
        const SizedBox(height: 14),
        // ── actions ──
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            if (run.status == FlowRunStatus.awaitingHuman) ...[
              FilledButton.icon(
                onPressed: () => _gate(true),
                icon: const Icon(Icons.check_circle_outline),
                label: Text(l10n.t('runs.approve')),
              ),
              OutlinedButton.icon(
                onPressed: () => _gate(false),
                icon: const Icon(Icons.cancel_outlined),
                label: Text(l10n.t('runs.reject')),
              ),
            ],
            if (!terminal) ...[
              if (run.currentStepId != null)
                OutlinedButton.icon(
                  onPressed: _skipCurrent,
                  icon: const Icon(Icons.skip_next),
                  label: Text(l10n.t('runs.skip')),
                ),
              if (run.status != FlowRunStatus.paused)
                OutlinedButton.icon(
                  onPressed: () => _control('pause'),
                  icon: const Icon(Icons.pause),
                  label: Text(l10n.t('runs.pause')),
                ),
              if (run.status == FlowRunStatus.paused)
                OutlinedButton.icon(
                  onPressed: () => _control('resume'),
                  icon: const Icon(Icons.play_arrow),
                  label: Text(l10n.t('runs.resume')),
                ),
              OutlinedButton.icon(
                onPressed: () => _control('cancel'),
                icon: const Icon(Icons.stop_circle_outlined),
                label: Text(l10n.t('runs.cancel')),
              ),
            ],
          ],
        ),
        // Parked on a FAILED step (not a human gate): explain what the two
        // resolutions actually do.
        if (run.status == FlowRunStatus.awaitingHuman &&
            _defsById[run.currentStepId?.value]?.kind != FlowStepKind.humanGate)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              l10n.t('runs.parkedRetryHint'),
              style: const TextStyle(fontSize: 12, color: OracleBrand.warning),
            ),
          ),
        const Divider(height: 30),
        _RunSectionSelector(
          value: _section,
          onChanged: (value) => setState(() => _section = value),
          dataCount: bundle.context.length + bundle.artifacts.length,
          sessionCount: bundle.steps
              .where((step) => step.sessionId != null)
              .map((step) => step.sessionId!.value)
              .toSet()
              .length,
          eventCount: bundle.events.length,
        ),
        const SizedBox(height: 18),
        // ── step cards: NOW → NEXT → the rest on demand ──
        if (_section == _RunSection.execution && orderedStepIds.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              run.status == FlowRunStatus.queued
                  ? l10n.t('runs.queuedHint')
                  : l10n.t('runs.noSteps'),
              style: const TextStyle(
                fontSize: 12.5,
                color: OracleBrand.gray400,
              ),
            ),
          ),
        if (_section == _RunSection.execution)
          ...() {
            final currentId = terminal ? null : run.currentStepId?.value;
            final hasCurrent =
                currentId != null && byStep.containsKey(currentId);
            final doneIds = [
              for (final id in orderedStepIds)
                if (!(hasCurrent && id == currentId)) id,
            ];
            final upcoming = [
              for (final d in _defs)
                if (!byStep.containsKey(d.id.value) && d.id.value != currentId)
                  d,
            ];
            return <Widget>[
              if (hasCurrent) ...[
                Text(
                  l10n.t('runs.currentStep'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                _StepCard(
                  def: _defsById[currentId],
                  iterations: byStep[currentId]!,
                ),
              ],
              if (!terminal && upcoming.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  l10n.t('runs.nextSteps'),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final d in upcoming)
                      Chip(
                        avatar: Icon(
                          kindIcon(d.kind),
                          size: 14,
                          color: kindColor(d.kind),
                        ),
                        label: Text(
                          d.stepKey,
                          style: const TextStyle(fontSize: 11.5),
                        ),
                        visualDensity: VisualDensity.compact,
                        side: BorderSide(
                          color: kindColor(d.kind).withValues(alpha: 0.35),
                        ),
                      ),
                  ],
                ),
              ],
              if (doneIds.isNotEmpty) ...[
                const SizedBox(height: 12),
                InkWell(
                  onTap: () => setState(() => _showDone = !_showDone),
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Icon(
                          _showDone ? Icons.expand_less : Icons.expand_more,
                          size: 18,
                          color: OracleBrand.gray400,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${l10n.t('runs.doneSteps')} (${doneIds.length})',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ],
                    ),
                  ),
                ),
                if (_showDone || !hasCurrent)
                  for (final stepId in doneIds)
                    _StepCard(
                      def: _defsById[stepId],
                      iterations: byStep[stepId]!,
                    ),
              ],
            ];
          }(),
        if (_section == _RunSection.sessions)
          _RunSessionsView(steps: bundle.steps, defsById: _defsById),
        // ── blackboard ──
        if (_section == _RunSection.data && bundle.context.isNotEmpty) ...[
          Text(
            l10n.t('runs.blackboard'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          for (final c in bundle.context) _BlackboardRow(entry: c),
        ],
        // ── artifacts ──
        if (_section == _RunSection.data && bundle.artifacts.isNotEmpty) ...[
          const Divider(height: 30),
          Text(
            l10n.t('runs.artifacts'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final artifact in bundle.artifacts)
                _ArtifactCard(artifact: artifact),
            ],
          ),
        ],
        if (_section == _RunSection.data &&
            bundle.context.isEmpty &&
            bundle.artifacts.isEmpty)
          _EmptySection(
            icon: Icons.inventory_2_outlined,
            message: l10n.t('runs.noDataYet'),
          ),
        // ── timeline ──
        if (_section == _RunSection.events) ...[
          Text(
            l10n.t('runs.timeline'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 10),
          if (bundle.events.isEmpty)
            _EmptySection(
              icon: Icons.history,
              message: l10n.t('runs.noEventsYet'),
            )
          else
            Container(
              decoration: BoxDecoration(
                color: OracleBrand.gray900.withValues(alpha: .45),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: OracleBrand.gray700),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(
                children: [
                  for (final e in bundle.events.take(100))
                    _EventRow(event: e, defsById: _defsById),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

class _RunProgressSummary extends StatelessWidget {
  final List<FlowStepEntity> definitions;
  final Map<String, FlowRunStepStatus?> statuses;
  final String? currentStepId;
  const _RunProgressSummary({
    required this.definitions,
    required this.statuses,
    required this.currentStepId,
  });

  @override
  Widget build(BuildContext context) {
    final completed = statuses.values
        .where(
          (status) =>
              status == FlowRunStepStatus.passed ||
              status == FlowRunStepStatus.skipped,
        )
        .length;
    final failed = statuses.values
        .where(
          (status) =>
              status == FlowRunStepStatus.failed ||
              status == FlowRunStepStatus.abandoned,
        )
        .length;
    final total = definitions.length;
    final progress = total == 0 ? 0.0 : completed / total;
    final current = definitions
        .where((definition) => definition.id.value == currentStepId)
        .firstOrNull;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: OracleBrand.gray900.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: OracleBrand.gray700),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '$completed / $total ${l10n.t('runs.stepsCompleted')}',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (current != null) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${l10n.t('runs.now')}: ${current.name.isEmpty ? current.stepKey : current.name}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: OracleBrand.violetSoft,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    backgroundColor: OracleBrand.gray800,
                    color: failed > 0
                        ? OracleBrand.warning
                        : OracleBrand.success,
                  ),
                ),
              ],
            ),
          ),
          if (failed > 0) ...[
            const SizedBox(width: 12),
            StatusBadge(
              '$failed ${l10n.t('runs.withIssue')}',
              color: OracleBrand.warning,
            ),
          ],
        ],
      ),
    );
  }
}

class _RunSectionSelector extends StatelessWidget {
  final _RunSection value;
  final ValueChanged<_RunSection> onChanged;
  final int dataCount;
  final int sessionCount;
  final int eventCount;
  const _RunSectionSelector({
    required this.value,
    required this.onChanged,
    required this.dataCount,
    required this.sessionCount,
    required this.eventCount,
  });

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: SegmentedButton<_RunSection>(
      segments: [
        ButtonSegment(
          value: _RunSection.execution,
          icon: const Icon(Icons.account_tree_outlined, size: 16),
          label: Text(l10n.t('runs.sectionExecution')),
        ),
        ButtonSegment(
          value: _RunSection.sessions,
          icon: const Icon(Icons.forum_outlined, size: 16),
          label: Text('${l10n.t('runs.sectionSessions')} ($sessionCount)'),
        ),
        ButtonSegment(
          value: _RunSection.data,
          icon: const Icon(Icons.data_object, size: 16),
          label: Text('${l10n.t('runs.sectionData')} ($dataCount)'),
        ),
        ButtonSegment(
          value: _RunSection.events,
          icon: const Icon(Icons.history, size: 16),
          label: Text('${l10n.t('runs.sectionEvents')} ($eventCount)'),
        ),
      ],
      selected: {value},
      onSelectionChanged: (selection) => onChanged(selection.first),
      showSelectedIcon: false,
      style: const ButtonStyle(
        visualDensity: VisualDensity.compact,
        textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12)),
      ),
    ),
  );
}

class _RunSessionsView extends StatelessWidget {
  final List<FlowRunStepEntity> steps;
  final Map<String, FlowStepEntity> defsById;
  const _RunSessionsView({required this.steps, required this.defsById});

  @override
  Widget build(BuildContext context) {
    final grouped = <String, List<FlowRunStepEntity>>{};
    for (final step in steps) {
      final key = step.sessionId?.value ?? 'missing:${step.id.value}';
      (grouped[key] ??= []).add(step);
    }
    final conversations = grouped.values.toList();
    for (final turns in conversations) {
      turns.sort((a, b) => a.iteration.compareTo(b.iteration));
    }
    conversations.sort(
      (a, b) => (a.first.startedAt ?? DateTime(1970)).compareTo(
        b.first.startedAt ?? DateTime(1970),
      ),
    );
    if (conversations.isEmpty) {
      return _EmptySection(
        icon: Icons.forum_outlined,
        message: l10n.t('runs.noSessionsYet'),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.t('runs.sectionSessions'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(
          '${conversations.where((turns) => turns.first.sessionId != null).length} ${l10n.t('runs.sessionLinked').toLowerCase()}',
          style: const TextStyle(fontSize: 12, color: OracleBrand.gray400),
        ),
        const SizedBox(height: 10),
        for (final turns in conversations)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: CircleAvatar(
                radius: 17,
                backgroundColor: stepStatusColor(
                  turns.last.status,
                ).withValues(alpha: .14),
                child: Icon(
                  turns.last.sessionId == null
                      ? Icons.link_off_outlined
                      : Icons.forum_outlined,
                  size: 17,
                  color: stepStatusColor(turns.last.status),
                ),
              ),
              title: Text(
                defsById[turns.last.stepId.value]?.name.isNotEmpty == true
                    ? defsById[turns.last.stepId.value]!.name
                    : defsById[turns.last.stepId.value]?.stepKey ??
                          turns.last.stepId.value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${agentLabel(turns.last.agent ?? 'agent')} · ${turns.length} ${l10n.t('runs.interactions')} · ${fmtDateTime(turns.last.startedAt)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (turns.last.agentSessionId != null)
                    Text(
                      '${l10n.t('runs.contextContinued')} · ${l10n.t('runs.nativeSession')}: ${turns.last.agentSessionId}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: OracleBrand.success,
                      ),
                    ),
                ],
              ),
              trailing: turns.last.sessionId == null
                  ? Tooltip(
                      message: l10n.t('runs.legacySessionMissing'),
                      child: const Icon(
                        Icons.info_outline,
                        color: OracleBrand.warning,
                      ),
                    )
                  : OutlinedButton.icon(
                      onPressed: () => _openRunSession(context, turns.last),
                      icon: const Icon(Icons.open_in_new, size: 16),
                      label: Text(l10n.t('runs.openSession')),
                    ),
            ),
          ),
      ],
    );
  }
}

Future<void> _openRunSession(
  BuildContext context,
  FlowRunStepEntity step,
) async {
  final sessionId = step.sessionId;
  if (sessionId == null) return;
  await showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 920,
        height: 720,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 14, 10, 14),
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              child: Row(
                children: [
                  const Icon(Icons.forum_outlined),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${l10n.t('runs.sectionSessions')} · ${agentLabel(step.agent ?? 'agent')}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          '${l10n.t('runs.iteration')} ${step.iteration} · ${sessionId.value}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontFamily: 'monospace',
                            color: OracleBrand.gray500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: l10n.t('common.close'),
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(child: _SessionTranscript(sessionId: sessionId)),
          ],
        ),
      ),
    ),
  );
}

class _SessionTurn {
  final RequestEntity request;
  final List<MessageEntity> messages;
  const _SessionTurn(this.request, this.messages);
}

class _SessionTranscript extends StatefulWidget {
  final IdVO sessionId;
  const _SessionTranscript({required this.sessionId});

  @override
  State<_SessionTranscript> createState() => _SessionTranscriptState();
}

class _SessionTranscriptState extends State<_SessionTranscript> {
  List<_SessionTurn>? _turns;
  Object? _error;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 2), (_) {
      _refresh(silent: true);
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<List<_SessionTurn>> _load() async {
    final requests = await injector
        .get<SessionRequestsUsecase>()(widget.sessionId, limit: 100)
        .then((result) => result.getOrDefault(const []));
    return Future.wait([
      for (final request in requests.reversed)
        injector.get<RequestMessagesUsecase>()(request.id, limit: 300).then(
          (result) => _SessionTurn(request, result.getOrDefault(const [])),
        ),
    ]);
  }

  Future<void> _refresh({bool silent = false}) async {
    try {
      final turns = await _load();
      if (mounted) {
        setState(() {
          _turns = turns;
          _error = null;
        });
      }
    } catch (error) {
      if (!silent && mounted) setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: OutlinedButton.icon(
          onPressed: _refresh,
          icon: const Icon(Icons.refresh),
          label: Text(l10n.t('app.retry')),
        ),
      );
    }
    final turns = _turns;
    if (turns == null) return const Center(child: CircularProgressIndicator());
    if (turns.isEmpty) {
      return _EmptySection(
        icon: Icons.hourglass_empty,
        message: l10n.t('runs.running'),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: turns.length,
      itemBuilder: (context, index) {
        final turn = turns[index];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Pane(
              icon: Icons.outgoing_mail,
              title: l10n.t('runs.sessionPrompt'),
              initiallyExpanded: index == turns.length - 1,
              child: MarkdownView(turn.request.userText.value),
            ),
            for (final message in turn.messages)
              _Pane(
                icon: switch (message.role) {
                  MessageRole.assistant => Icons.smart_toy_outlined,
                  MessageRole.tool => Icons.build_outlined,
                  MessageRole.system => Icons.info_outline,
                  MessageRole.user => Icons.person_outline,
                },
                title: '${l10n.t('runs.sessionAnswer')} · ${message.role.code}',
                initiallyExpanded: true,
                child: MarkdownView(message.content.value),
              ),
            if (index < turns.length - 1) const Divider(height: 28),
          ],
        );
      },
    );
  }
}

class _EmptySection extends StatelessWidget {
  final IconData icon;
  final String message;
  const _EmptySection({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
    decoration: BoxDecoration(
      color: OracleBrand.gray900.withValues(alpha: .35),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: OracleBrand.gray700),
    ),
    child: Column(
      children: [
        Icon(icon, size: 26, color: OracleBrand.gray500),
        const SizedBox(height: 8),
        Text(message, style: const TextStyle(color: OracleBrand.gray400)),
      ],
    ),
  );
}

class _ArtifactCard extends StatelessWidget {
  final FlowArtifactEntity artifact;
  const _ArtifactCard({required this.artifact});

  IconData get _icon => switch (artifact.kind) {
    'branch' => Icons.merge_type,
    'commit' => Icons.commit,
    'pr' => Icons.call_merge,
    'rfc' || 'doc' => Icons.description_outlined,
    'file' => Icons.insert_drive_file_outlined,
    'memory' => Icons.psychology_outlined,
    'run' => Icons.play_circle_outline,
    _ => Icons.inventory_2_outlined,
  };

  @override
  Widget build(BuildContext context) => Container(
    width: 320,
    padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
    decoration: BoxDecoration(
      color: OracleBrand.gray900.withValues(alpha: .65),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: OracleBrand.gray700),
    ),
    child: Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: OracleBrand.blue.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(_icon, size: 18, color: OracleBrand.blue),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                artifact.kind.toUpperCase(),
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: OracleBrand.gray500,
                ),
              ),
              const SizedBox(height: 3),
              SelectableText(
                artifact.locator,
                maxLines: 2,
                style: const TextStyle(fontSize: 11.5),
              ),
            ],
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: l10n.t('runs.copy'),
          icon: const Icon(Icons.copy, size: 14, color: OracleBrand.gray500),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: artifact.locator));
            showSnack(context, l10n.t('runs.copied'));
          },
        ),
      ],
    ),
  );
}

/// A live, zoomable execution map. Unlike the old linear strip, this preserves
/// forks, loop-backs and joins from the process canvas, so the operator sees
/// the real route being executed.
class _RunGraph extends StatefulWidget {
  final List<FlowStepEntity> definitions;
  final List<FlowEdgeEntity> edges;
  final Map<String, FlowRunStepStatus?> statuses;
  final String? currentStepId;
  final Set<String> traversedEdgeIds;

  const _RunGraph({
    required this.definitions,
    required this.edges,
    required this.statuses,
    required this.currentStepId,
    required this.traversedEdgeIds,
  });

  static const nodeSize = Size(164, 66);

  @override
  State<_RunGraph> createState() => _RunGraphState();
}

class _RunGraphState extends State<_RunGraph> {
  final TransformationController _transform = TransformationController();

  List<FlowStepEntity> get definitions => widget.definitions;
  List<FlowEdgeEntity> get edges => widget.edges;
  Map<String, FlowRunStepStatus?> get statuses => widget.statuses;
  String? get currentStepId => widget.currentStepId;

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  void _scaleBy(double factor) {
    final current = _transform.value.getMaxScaleOnAxis();
    final next = (current * factor).clamp(.35, 2.2);
    if ((next - current).abs() < .001) return;
    final ratio = next / current;
    _transform.value = _transform.value.clone()
      ..scaleByDouble(ratio, ratio, ratio, 1);
  }

  void _pointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent ||
        !HardwareKeyboard.instance.isControlPressed) {
      return;
    }
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      _scaleBy(event.scrollDelta.dy > 0 ? .88 : 1.14);
    });
  }

  void _reset() => _transform.value = Matrix4.identity();

  @override
  Widget build(BuildContext context) {
    final raw = <String, Offset>{};
    var hasLayout = false;
    for (var index = 0; index < definitions.length; index++) {
      final step = definitions[index];
      try {
        final config = jsonDecode(step.config);
        final ui = config is Map ? config['ui'] : null;
        if (ui is Map && ui['x'] is num && ui['y'] is num) {
          raw[step.id.value] = Offset(
            (ui['x'] as num).toDouble(),
            (ui['y'] as num).toDouble(),
          );
          hasLayout = true;
          continue;
        }
      } catch (_) {
        // Fall back to a readable grid for legacy definitions.
      }
      raw[step.id.value] = Offset((index % 4) * 220.0, (index ~/ 4) * 120.0);
    }
    if (!hasLayout) {
      for (var index = 0; index < definitions.length; index++) {
        raw[definitions[index].id.value] = Offset(
          (index % 4) * 220.0,
          (index ~/ 4) * 120.0,
        );
      }
    }
    final minX = raw.values.map((p) => p.dx).reduce(math.min);
    final minY = raw.values.map((p) => p.dy).reduce(math.min);
    final positions = {
      for (final entry in raw.entries)
        entry.key: entry.value - Offset(minX, minY) + const Offset(92, 82),
    };
    final width = math.max(
      760.0,
      positions.values.map((p) => p.dx).reduce(math.max) +
          _RunGraph.nodeSize.width +
          120,
    );
    final height = math.max(
      220.0,
      positions.values.map((p) => p.dy).reduce(math.max) +
          _RunGraph.nodeSize.height +
          120,
    );
    final routes = _RunEdgeRouter.routeAll(edges, positions);

    return Container(
      height: math.min(410, math.max(250, height)),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: OracleBrand.gray950.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: OracleBrand.gray700),
      ),
      child: Listener(
        onPointerSignal: _pointerSignal,
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(painter: const _DotGridPainter()),
            ),
            InteractiveViewer(
              transformationController: _transform,
              constrained: false,
              minScale: .35,
              maxScale: 2.2,
              boundaryMargin: const EdgeInsets.all(240),
              panEnabled: true,
              // Native wheel zoom is disabled so a normal wheel gesture keeps
              // scrolling the page. Ctrl+wheel is handled above and claimed by
              // the pointer-signal resolver only for this graph.
              scaleEnabled: false,
              child: SizedBox(
                width: width,
                height: height,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _RunEdgesPainter(
                          edges: edges,
                          routes: routes,
                          statuses: statuses,
                          currentStepId: currentStepId,
                          traversedEdgeIds: widget.traversedEdgeIds,
                        ),
                      ),
                    ),
                    for (final step in definitions)
                      Positioned(
                        left: positions[step.id.value]!.dx,
                        top: positions[step.id.value]!.dy,
                        width: _RunGraph.nodeSize.width,
                        height: _RunGraph.nodeSize.height,
                        child: _RunNode(
                          definition: step,
                          status: statuses[step.id.value],
                          current: step.id.value == currentStepId,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Positioned(
              right: 10,
              top: 10,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _GraphButton(
                    icon: Icons.remove,
                    tooltip: l10n.t('runs.zoomOut'),
                    onPressed: () => _scaleBy(1 / 1.2),
                  ),
                  const SizedBox(width: 4),
                  _GraphButton(
                    icon: Icons.add,
                    tooltip: l10n.t('runs.zoomIn'),
                    onPressed: () => _scaleBy(1.2),
                  ),
                  const SizedBox(width: 4),
                  _GraphButton(
                    icon: Icons.center_focus_strong,
                    tooltip: l10n.t('runs.resetView'),
                    onPressed: _reset,
                  ),
                ],
              ),
            ),
            Positioned(
              left: 10,
              bottom: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: OracleBrand.gray900.withValues(alpha: .92),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: OracleBrand.gray700),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.pan_tool_alt_outlined,
                      size: 13,
                      color: OracleBrand.gray400,
                    ),
                    SizedBox(width: 5),
                    Text(
                      l10n.t('runs.graphHint'),
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: OracleBrand.gray400,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GraphButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  const _GraphButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Material(
      color: OracleBrand.gray900.withValues(alpha: .94),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: OracleBrand.gray700),
      ),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 30,
          height: 30,
          child: Icon(icon, size: 16, color: OracleBrand.gray400),
        ),
      ),
    ),
  );
}

class _RunNode extends StatelessWidget {
  final FlowStepEntity definition;
  final FlowRunStepStatus? status;
  final bool current;
  const _RunNode({
    required this.definition,
    required this.status,
    required this.current,
  });

  @override
  Widget build(BuildContext context) {
    final color = status == null
        ? OracleBrand.gray500
        : stepStatusColor(status!);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: current
            ? color.withValues(alpha: .15)
            : OracleBrand.gray900.withValues(alpha: .97),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color, width: current ? 2 : 1),
        boxShadow: current
            ? [BoxShadow(color: color.withValues(alpha: .24), blurRadius: 14)]
            : null,
      ),
      child: Row(
        children: [
          if (status == FlowRunStepStatus.running ||
              status == FlowRunStepStatus.verifying)
            SizedBox(
              width: 19,
              height: 19,
              child: CircularProgressIndicator(strokeWidth: 2, color: color),
            )
          else
            Icon(kindIcon(definition.kind), size: 19, color: color),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  definition.name.isEmpty
                      ? definition.stepKey
                      : definition.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  status == null
                      ? l10n.t('runs.pending')
                      : stepStatusLabel(status!),
                  maxLines: 1,
                  style: TextStyle(fontSize: 10.5, color: color),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _RunPortSide { left, right, top, bottom }

class _RunEdgeRoute {
  final List<Offset> points;
  final Offset label;
  const _RunEdgeRoute(this.points, this.label);
}

/// Compact obstacle-aware router for the monitor. It mirrors the editor's
/// orthogonal routing, spreads parallel ports and penalizes crossings so the
/// execution view preserves the authored layout without drawing through cards.
class _RunEdgeRouter {
  static const _stub = 20.0;

  static Map<String, _RunEdgeRoute> routeAll(
    List<FlowEdgeEntity> edges,
    Map<String, Offset> positions,
  ) {
    final sides = <String, (_RunPortSide, _RunPortSide)>{};
    for (final edge in edges) {
      final from = positions[edge.fromStep.value];
      final to = positions[edge.toStep.value];
      if (from == null || to == null) continue;
      final a = from + _RunGraph.nodeSize.center(Offset.zero);
      final b = to + _RunGraph.nodeSize.center(Offset.zero);
      final dx = b.dx - a.dx;
      final dy = b.dy - a.dy;
      sides[edge.id.value] = dx.abs() >= dy.abs() * .8
          ? dx >= 0
                ? (_RunPortSide.right, _RunPortSide.left)
                : (_RunPortSide.left, _RunPortSide.right)
          : dy >= 0
          ? (_RunPortSide.bottom, _RunPortSide.top)
          : (_RunPortSide.top, _RunPortSide.bottom);
    }

    final sourceGroups = <String, List<FlowEdgeEntity>>{};
    final targetGroups = <String, List<FlowEdgeEntity>>{};
    for (final edge in edges) {
      final pair = sides[edge.id.value];
      if (pair == null) continue;
      (sourceGroups['${edge.fromStep.value}:${pair.$1.name}'] ??= []).add(edge);
      (targetGroups['${edge.toStep.value}:${pair.$2.name}'] ??= []).add(edge);
    }
    for (final group in [...sourceGroups.values, ...targetGroups.values]) {
      group.sort((a, b) => a.id.value.compareTo(b.id.value));
    }

    final result = <String, _RunEdgeRoute>{};
    final placed = <(Offset, Offset)>[];
    for (var ordinal = 0; ordinal < edges.length; ordinal++) {
      final edge = edges[ordinal];
      final pair = sides[edge.id.value];
      final from = positions[edge.fromStep.value];
      final to = positions[edge.toStep.value];
      if (pair == null || from == null || to == null) continue;
      final sourceGroup =
          sourceGroups['${edge.fromStep.value}:${pair.$1.name}']!;
      final targetGroup = targetGroups['${edge.toStep.value}:${pair.$2.name}']!;
      final start = _anchor(
        from,
        pair.$1,
        sourceGroup.indexOf(edge),
        sourceGroup.length,
      );
      final end = _anchor(
        to,
        pair.$2,
        targetGroup.indexOf(edge),
        targetGroup.length,
      );
      final obstacles = <Rect>[
        for (final entry in positions.entries)
          if (entry.key != edge.fromStep.value &&
              entry.key != edge.toStep.value)
            entry.value & _RunGraph.nodeSize,
      ];
      final route = _bestRoute(
        start,
        end,
        pair.$1,
        pair.$2,
        obstacles,
        placed,
        ordinal,
      );
      result[edge.id.value] = route;
      for (var i = 0; i < route.points.length - 1; i++) {
        placed.add((route.points[i], route.points[i + 1]));
      }
    }
    return result;
  }

  static Offset _anchor(
    Offset position,
    _RunPortSide side,
    int index,
    int count,
  ) {
    final horizontal = side == _RunPortSide.top || side == _RunPortSide.bottom;
    final span =
        (horizontal ? _RunGraph.nodeSize.width : _RunGraph.nodeSize.height) -
        24;
    final gap = count <= 1 ? 0.0 : (span / (count - 1)).clamp(0.0, 14.0);
    final shift = (index - (count - 1) / 2) * gap;
    return switch (side) {
      _RunPortSide.left =>
        position + Offset(0, _RunGraph.nodeSize.height / 2 + shift),
      _RunPortSide.right =>
        position +
            Offset(
              _RunGraph.nodeSize.width,
              _RunGraph.nodeSize.height / 2 + shift,
            ),
      _RunPortSide.top =>
        position + Offset(_RunGraph.nodeSize.width / 2 + shift, 0),
      _RunPortSide.bottom =>
        position +
            Offset(
              _RunGraph.nodeSize.width / 2 + shift,
              _RunGraph.nodeSize.height,
            ),
    };
  }

  static Offset _unit(_RunPortSide side) => switch (side) {
    _RunPortSide.left => const Offset(-1, 0),
    _RunPortSide.right => const Offset(1, 0),
    _RunPortSide.top => const Offset(0, -1),
    _RunPortSide.bottom => const Offset(0, 1),
  };

  static _RunEdgeRoute _bestRoute(
    Offset first,
    Offset last,
    _RunPortSide sourceSide,
    _RunPortSide targetSide,
    List<Rect> obstacles,
    List<(Offset, Offset)> placed,
    int ordinal,
  ) {
    final start = first + _unit(sourceSide) * _stub;
    final end = last + _unit(targetSide) * _stub;
    final candidates = <List<Offset>>[];
    final horizontal =
        sourceSide == _RunPortSide.left || sourceSide == _RunPortSide.right;
    final nudge = (ordinal % 5 - 2) * 7.0;
    if (horizontal) {
      final middle = (start.dx + end.dx) / 2 + nudge;
      candidates.add([
        first,
        start,
        Offset(middle, start.dy),
        Offset(middle, end.dy),
        end,
        last,
      ]);
      final top =
          obstacles.fold(
            math.min(first.dy, last.dy),
            (value, rect) => math.min(value, rect.top),
          ) -
          42 -
          nudge.abs();
      final bottom =
          obstacles.fold(
            math.max(first.dy, last.dy),
            (value, rect) => math.max(value, rect.bottom),
          ) +
          42 +
          nudge.abs();
      candidates.add([
        first,
        start,
        Offset(start.dx, top),
        Offset(end.dx, top),
        end,
        last,
      ]);
      candidates.add([
        first,
        start,
        Offset(start.dx, bottom),
        Offset(end.dx, bottom),
        end,
        last,
      ]);
    } else {
      final middle = (start.dy + end.dy) / 2 + nudge;
      candidates.add([
        first,
        start,
        Offset(start.dx, middle),
        Offset(end.dx, middle),
        end,
        last,
      ]);
      final left =
          obstacles.fold(
            math.min(first.dx, last.dx),
            (value, rect) => math.min(value, rect.left),
          ) -
          42 -
          nudge.abs();
      final right =
          obstacles.fold(
            math.max(first.dx, last.dx),
            (value, rect) => math.max(value, rect.right),
          ) +
          42 +
          nudge.abs();
      candidates.add([
        first,
        start,
        Offset(left, start.dy),
        Offset(left, end.dy),
        end,
        last,
      ]);
      candidates.add([
        first,
        start,
        Offset(right, start.dy),
        Offset(right, end.dy),
        end,
        last,
      ]);
    }

    List<Offset>? best;
    var bestScore = double.infinity;
    for (final raw in candidates) {
      final points = _simplify(raw);
      var score = (points.length - 2) * 14.0;
      for (var i = 0; i < points.length - 1; i++) {
        final a = points[i];
        final b = points[i + 1];
        score += (b - a).distance;
        for (final obstacle in obstacles) {
          if (_segmentHitsRect(a, b, obstacle.inflate(12))) score += 100000;
        }
        for (final old in placed) {
          if (_segmentsCross(a, b, old.$1, old.$2)) score += 600;
          if (_segmentsOverlap(a, b, old.$1, old.$2)) score += 900;
        }
      }
      if (score < bestScore) {
        bestScore = score;
        best = points;
      }
    }
    final points = best!;
    var label = (first + last) / 2;
    var longest = 0.0;
    for (var i = 1; i < points.length - 2; i++) {
      final length = (points[i + 1] - points[i]).distance;
      if (length > longest) {
        longest = length;
        label = (points[i] + points[i + 1]) / 2;
      }
    }
    return _RunEdgeRoute(points, label);
  }

  static List<Offset> _simplify(List<Offset> input) {
    final result = <Offset>[];
    for (final point in input) {
      if (result.isNotEmpty && (result.last - point).distance < .5) continue;
      if (result.length >= 2) {
        final a = result[result.length - 2];
        final b = result.last;
        final sameX = (a.dx - b.dx).abs() < .5 && (b.dx - point.dx).abs() < .5;
        final sameY = (a.dy - b.dy).abs() < .5 && (b.dy - point.dy).abs() < .5;
        if (sameX || sameY) result.removeLast();
      }
      result.add(point);
    }
    return result;
  }

  static bool _segmentHitsRect(Offset a, Offset b, Rect rect) {
    if ((a.dx - b.dx).abs() < .5) {
      return a.dx > rect.left &&
          a.dx < rect.right &&
          math.min(a.dy, b.dy) < rect.bottom &&
          math.max(a.dy, b.dy) > rect.top;
    }
    return a.dy > rect.top &&
        a.dy < rect.bottom &&
        math.min(a.dx, b.dx) < rect.right &&
        math.max(a.dx, b.dx) > rect.left;
  }

  static bool _segmentsCross(Offset a, Offset b, Offset c, Offset d) {
    final firstVertical = (a.dx - b.dx).abs() < .5;
    final secondVertical = (c.dx - d.dx).abs() < .5;
    if (firstVertical == secondVertical) return false;
    final verticalA = firstVertical ? a : c;
    final verticalB = firstVertical ? b : d;
    final horizontalA = firstVertical ? c : a;
    final horizontalB = firstVertical ? d : b;
    return verticalA.dx > math.min(horizontalA.dx, horizontalB.dx) &&
        verticalA.dx < math.max(horizontalA.dx, horizontalB.dx) &&
        horizontalA.dy > math.min(verticalA.dy, verticalB.dy) &&
        horizontalA.dy < math.max(verticalA.dy, verticalB.dy);
  }

  static bool _segmentsOverlap(Offset a, Offset b, Offset c, Offset d) {
    final firstVertical = (a.dx - b.dx).abs() < .5;
    final secondVertical = (c.dx - d.dx).abs() < .5;
    if (firstVertical != secondVertical) return false;
    if (firstVertical) {
      return (a.dx - c.dx).abs() <= 2 &&
          math.min(a.dy, b.dy) < math.max(c.dy, d.dy) &&
          math.min(c.dy, d.dy) < math.max(a.dy, b.dy);
    }
    return (a.dy - c.dy).abs() <= 2 &&
        math.min(a.dx, b.dx) < math.max(c.dx, d.dx) &&
        math.min(c.dx, d.dx) < math.max(a.dx, b.dx);
  }
}

class _RunEdgesPainter extends CustomPainter {
  final List<FlowEdgeEntity> edges;
  final Map<String, _RunEdgeRoute> routes;
  final Map<String, FlowRunStepStatus?> statuses;
  final String? currentStepId;
  final Set<String> traversedEdgeIds;

  _RunEdgesPainter({
    required this.edges,
    required this.routes,
    required this.statuses,
    required this.currentStepId,
    required this.traversedEdgeIds,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final ordered = [...edges]
      ..sort(
        (a, b) => (traversedEdgeIds.contains(a.id.value) ? 1 : 0).compareTo(
          traversedEdgeIds.contains(b.id.value) ? 1 : 0,
        ),
      );
    for (final edge in ordered) {
      final route = routes[edge.id.value];
      if (route == null || route.points.length < 2) continue;
      final traversed = traversedEdgeIds.contains(edge.id.value);
      final active = traversed && edge.toStep.value == currentStepId;
      final color = active
          ? OracleBrand.blue
          : !traversed
          ? OracleBrand.gray500
          : edge.condition == 'failure'
          ? OracleBrand.error
          : OracleBrand.success;
      final alpha = traversed ? 1.0 : .24;
      final width = active
          ? 3.2
          : traversed
          ? 2.4
          : 1.15;
      final path = _roundedPath(route.points);
      if (active) {
        canvas.drawPath(
          path,
          Paint()
            ..color = color.withValues(alpha: .2)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 10
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
        );
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = OracleBrand.gray950.withValues(alpha: .9 * alpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = width + 4
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = color.withValues(alpha: alpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
      _drawArrow(canvas, route.points, color.withValues(alpha: alpha));
      if (traversed) _drawLabel(canvas, edge, route.label, color);
    }
  }

  Path _roundedPath(List<Offset> points) {
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length - 1; i++) {
      final previous = points[i - 1];
      final corner = points[i];
      final next = points[i + 1];
      final incoming = (corner - previous).distance;
      final outgoing = (next - corner).distance;
      final radius = math.min(math.min(incoming, outgoing), 8.0);
      if (radius < 1) {
        path.lineTo(corner.dx, corner.dy);
        continue;
      }
      final before = corner + (previous - corner) / incoming * radius;
      final after = corner + (next - corner) / outgoing * radius;
      path.lineTo(before.dx, before.dy);
      path.quadraticBezierTo(corner.dx, corner.dy, after.dx, after.dy);
    }
    path.lineTo(points.last.dx, points.last.dy);
    return path;
  }

  void _drawArrow(Canvas canvas, List<Offset> points, Color color) {
    final tip = points.last;
    final delta = tip - points[points.length - 2];
    if (delta.distance == 0) return;
    final direction = delta / delta.distance;
    final normal = Offset(-direction.dy, direction.dx);
    final base = tip - direction * 8;
    final arrow = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo((base + normal * 4).dx, (base + normal * 4).dy)
      ..lineTo((base - normal * 4).dx, (base - normal * 4).dy)
      ..close();
    canvas.drawPath(arrow, Paint()..color = color);
  }

  void _drawLabel(
    Canvas canvas,
    FlowEdgeEntity edge,
    Offset center,
    Color color,
  ) {
    final label = edge.condition == 'verdict'
        ? (edge.verdictValue ?? conditionLabel(edge.condition))
        : conditionLabel(edge.condition);
    final text = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: color,
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: 120);
    final rect = Rect.fromCenter(
      center: center,
      width: text.width + 14,
      height: text.height + 7,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(7)),
      Paint()..color = OracleBrand.gray900.withValues(alpha: .96),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(7)),
      Paint()
        ..color = color.withValues(alpha: .6)
        ..style = PaintingStyle.stroke,
    );
    text.paint(canvas, Offset(rect.left + 7, rect.top + 3.5));
  }

  @override
  bool shouldRepaint(covariant _RunEdgesPainter oldDelegate) =>
      oldDelegate.currentStepId != currentStepId ||
      oldDelegate.statuses.toString() != statuses.toString() ||
      oldDelegate.traversedEdgeIds.toString() != traversedEdgeIds.toString() ||
      oldDelegate.edges != edges ||
      oldDelegate.routes != routes;
}

class _DotGridPainter extends CustomPainter {
  const _DotGridPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = OracleBrand.gray700.withValues(alpha: .45);
    for (double x = 14; x < size.width; x += 22) {
      for (double y = 14; y < size.height; y += 22) {
        canvas.drawCircle(Offset(x, y), .8, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Older Codex runs stored the cumulative thread usage on every resumed turn.
/// New runs persist a marker and already store the per-turn delta. Normalize
/// legacy rows only for display so their second/third iterations are not
/// presented as if each one consumed the entire conversation again.
Map<String, int> _displayTokensByIteration(List<FlowRunStepEntity> iterations) {
  final ordered = [...iterations]
    ..sort((a, b) => a.iteration.compareTo(b.iteration));
  final result = <String, int>{};
  FlowRunStepEntity? previous;
  for (final item in ordered) {
    final prior = previous;
    var tokens = item.tokensUsed;
    var hasSessionTotalMarker = false;
    try {
      final verifier = jsonDecode(item.verifier ?? '{}');
      hasSessionTotalMarker =
          verifier is Map && verifier['agentSessionTotalTokens'] is num;
    } catch (_) {
      // Legacy/malformed verifier: use the conservative fallback below.
    }
    if (!hasSessionTotalMarker &&
        item.agent == 'codex' &&
        prior != null &&
        prior.agentSessionId != null &&
        item.agentSessionId == prior.agentSessionId &&
        item.tokensUsed >= prior.tokensUsed) {
      tokens = item.tokensUsed - prior.tokensUsed;
    }
    result[item.id.value] = tokens;
    previous = item;
  }
  return result;
}

/// One STEP of the run: header (key, status, agent, totals) + its iterations.
class _StepCard extends StatelessWidget {
  final FlowStepEntity? def;
  final List<FlowRunStepEntity> iterations;
  const _StepCard({required this.def, required this.iterations});

  @override
  Widget build(BuildContext context) {
    final last = iterations.last;
    final title = def?.stepKey ?? last.stepId.value.substring(0, 8);
    final displayTokens = _displayTokensByIteration(iterations);
    final tokens = displayTokens.values.fold<int>(0, (a, b) => a + b);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          leading: Icon(
            def == null ? Icons.layers_outlined : kindIcon(def!.kind),
            size: 20,
            color: def == null ? OracleBrand.gray500 : kindColor(def!.kind),
          ),
          title: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    if (def != null && def!.name.isNotEmpty)
                      Text(
                        def!.name,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: OracleBrand.gray500,
                        ),
                      ),
                  ],
                ),
              ),
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (last.agent != null)
                    MetaChip(
                      agentLabel(last.agent!),
                      icon: Icons.smart_toy_outlined,
                    ),
                  if (iterations.length > 1)
                    MetaChip(
                      '${iterations.length}× ${l10n.t('runs.iterations')}',
                      icon: Icons.loop,
                    ),
                  if (tokens > 0)
                    MetaChip(
                      '$tokens ${l10n.t('runs.tokens')}',
                      icon: Icons.toll_outlined,
                    ),
                  StatusBadge(
                    stepStatusLabel(last.status),
                    color: stepStatusColor(last.status),
                  ),
                ],
              ),
            ],
          ),
          children: [
            for (final it in iterations.reversed)
              _IterationView(
                iteration: it,
                displayTokens: displayTokens[it.id.value] ?? it.tokensUsed,
                initiallyExpanded: it.iteration == last.iteration,
                single: iterations.length == 1,
              ),
          ],
        ),
      ),
    );
  }
}

/// One ITERATION: status header + the four structured panes.
class _IterationView extends StatelessWidget {
  final FlowRunStepEntity iteration;
  final int displayTokens;
  final bool initiallyExpanded;
  final bool single;
  const _IterationView({
    required this.iteration,
    required this.displayTokens,
    required this.initiallyExpanded,
    required this.single,
  });

  @override
  Widget build(BuildContext context) {
    final it = iteration;
    final duration = _fmtDuration(it.startedAt, it.endedAt);
    final header = Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (!single) ...[
          Text(
            '${l10n.t('runs.iteration')} ${it.iteration}',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5),
          ),
          StatusBadge(
            stepStatusLabel(it.status),
            color: stepStatusColor(it.status),
          ),
        ],
        if (duration != null) MetaChip(duration, icon: Icons.timer_outlined),
        if (displayTokens > 0)
          MetaChip(
            '$displayTokens ${l10n.t('runs.tokens')}',
            icon: Icons.toll_outlined,
          ),
        if (it.sessionId != null)
          OutlinedButton.icon(
            onPressed: () => _openRunSession(context, it),
            icon: const Icon(Icons.forum_outlined, size: 15),
            label: Text(l10n.t('runs.openSession')),
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
          ),
      ],
    );

    final panes = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if ((it.renderedPrompt ?? '').trim().isNotEmpty)
          _Pane(
            icon: Icons.chat_outlined,
            title: l10n.t('runs.promptSent'),
            copyText: it.renderedPrompt!,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: OracleBrand.gray950,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: OracleBrand.gray700),
              ),
              child: MarkdownView(
                it.renderedPrompt!,
                style: const TextStyle(fontSize: 12.5, height: 1.5),
              ),
            ),
          ),
        if ((it.report ?? '').trim().isNotEmpty)
          _Pane(
            icon: Icons.assignment_turned_in_outlined,
            title: l10n.t('runs.agentReport'),
            copyText: it.report!,
            initiallyExpanded: true,
            child: _ReportView(reportJson: it.report!),
          ),
        if ((it.verifier ?? '').trim().isNotEmpty)
          _Pane(
            icon: Icons.rule_outlined,
            title: l10n.t('runs.verifierOut'),
            copyText: it.verifier!,
            initiallyExpanded: it.status == FlowRunStepStatus.failed,
            child: _VerifierView(verifierJson: it.verifier!),
          ),
        _Pane(
          icon: Icons.data_object,
          title: l10n.t('runs.technical'),
          child: _TechView(iteration: it),
        ),
        if ((it.renderedPrompt ?? '').trim().isEmpty &&
            (it.report ?? '').trim().isEmpty &&
            (it.verifier ?? '').trim().isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              l10n.t('runs.running'),
              style: const TextStyle(fontSize: 12, color: OracleBrand.gray400),
            ),
          ),
      ],
    );

    if (single) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [header, const SizedBox(height: 4), panes],
      );
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: OracleBrand.gray950.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: OracleBrand.gray700),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          title: header,
          children: [panes],
        ),
      ),
    );
  }
}

/// A titled, collapsible pane with icon + copy button — the unit of the
/// iteration detail.
class _Pane extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget child;
  final String? copyText;
  final bool initiallyExpanded;
  const _Pane({
    required this.icon,
    required this.title,
    required this.child,
    this.copyText,
    this.initiallyExpanded = false,
  });

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        dense: true,
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 10),
        title: Row(
          children: [
            Icon(icon, size: 15, color: OracleBrand.gray400),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: OracleBrand.gray400,
              ),
            ),
            const Spacer(),
            if (copyText != null)
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: l10n.t('runs.copy'),
                icon: const Icon(
                  Icons.copy,
                  size: 13,
                  color: OracleBrand.gray500,
                ),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: copyText!));
                  showSnack(context, l10n.t('runs.copied'));
                },
              ),
          ],
        ),
        children: [child],
      ),
    );
  }
}

/// The agent's structured report: summary as markdown, outputs as key→value
/// rows, files touched as chips, open questions as bullets. Raw JSON only as
/// fallback.
class _ReportView extends StatelessWidget {
  final String reportJson;
  const _ReportView({required this.reportJson});

  @override
  Widget build(BuildContext context) {
    Map<String, dynamic>? j;
    try {
      final decoded = jsonDecode(reportJson);
      if (decoded is Map<String, dynamic>) j = decoded;
    } catch (_) {
      /* raw */
    }
    if (j == null) return _rawBox(reportJson);

    final summary = '${j['summary'] ?? ''}'.trim();
    final outputs = j['outputs'];
    final files = j['filesTouched'];
    final questions = j['openQuestions'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (summary.isNotEmpty)
          MarkdownView(
            summary,
            style: const TextStyle(fontSize: 12.5, height: 1.5),
          ),
        if (outputs is Map && outputs.isNotEmpty) ...[
          const SizedBox(height: 8),
          _fieldLabel(l10n.t('runs.outputs')),
          for (final e in outputs.entries)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: SelectableText(
                '${e.key}: ${e.value}',
                style: const TextStyle(
                  fontSize: 12,
                  color: OracleBrand.gray400,
                ),
              ),
            ),
        ],
        if (files is List && files.isNotEmpty) ...[
          const SizedBox(height: 8),
          _fieldLabel(l10n.t('runs.filesTouched')),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final f in files)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: OracleBrand.gray800,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '$f',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                    ),
                  ),
                ),
            ],
          ),
        ],
        if (questions is List && questions.isNotEmpty) ...[
          const SizedBox(height: 8),
          _fieldLabel(l10n.t('runs.openQuestions')),
          for (final q in questions)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '• $q',
                style: const TextStyle(
                  fontSize: 12,
                  color: OracleBrand.warning,
                ),
              ),
            ),
        ],
      ],
    );
  }

  Widget _fieldLabel(String text) => Text(
    text,
    style: const TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      color: OracleBrand.gray500,
    ),
  );
}

/// The verification pane: the agent launch result + each verifier COMMAND with
/// its pass/fail state, then the remaining output as a log box.
class _VerifierView extends StatelessWidget {
  final String verifierJson;
  const _VerifierView({required this.verifierJson});

  @override
  Widget build(BuildContext context) {
    Map<String, dynamic>? j;
    try {
      final decoded = jsonDecode(verifierJson);
      if (decoded is Map<String, dynamic>) j = decoded;
    } catch (_) {
      /* raw */
    }
    if (j == null) return _rawBox(verifierJson);

    final command = '${j['command'] ?? ''}'.trim();
    final launch = '${j['launch'] ?? ''}'.trim();
    final requirement = '${j['requirement'] ?? ''}'.trim();
    final passed = j['passed'] == true;
    final running = j['running'] == true;
    final subflowKey = '${j['subflow'] ?? ''}'.trim();
    final childRunId = '${j['childRunId'] ?? ''}'.trim();
    // The agent process itself: "exit 0" in the launch line = it completed.
    final agentRan = launch.isEmpty || launch.contains('exit 0');
    final details = '${j['details'] ?? ''}';
    final commandLines = <(String, bool)>[];
    final outputLines = <String>[];
    for (final line in const LineSplitter().convert(details)) {
      final m = RegExp(r'^\$ (.*) -> exit (-?\d+)').firstMatch(line.trim());
      if (m != null) {
        commandLines.add((m.group(1)!, m.group(2) == '0'));
      } else if (line.trim().isNotEmpty) {
        outputLines.add(line);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The exact invocation that launched the agent / command step.
        if (command.isNotEmpty) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${l10n.t('runs.launchCmd')}: ',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: OracleBrand.gray500,
                ),
              ),
              Expanded(
                child: SelectableText(
                  command,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11.5,
                    color: OracleBrand.gray100,
                  ),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: l10n.t('runs.copy'),
                icon: const Icon(
                  Icons.copy,
                  size: 13,
                  color: OracleBrand.gray500,
                ),
                onPressed: () =>
                    Clipboard.setData(ClipboardData(text: command)),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        // Persisted at LAUNCH time: the step is still executing — show that
        // instead of a misleading red "failed".
        if (running) ...[
          Row(
            children: [
              const SizedBox(
                width: 13,
                height: 13,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 8),
              Text(
                l10n.t('runs.verifRunning'),
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: OracleBrand.violet,
                ),
              ),
            ],
          ),
        ],
        // A subflow step: which process ran and the child run's id.
        if (subflowKey.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.account_tree_outlined,
                  size: 15,
                  color: OracleBrand.success,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: SelectableText(
                    '${l10n.t('runs.subflowRan')}: $subflowKey'
                    '${childRunId.isEmpty ? '' : ' · run $childRunId'}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: OracleBrand.gray400,
                    ),
                  ),
                ),
              ],
            ),
          ),
        // 1) The AGENT process result (its own line — a failed agent must never
        // hide behind a green "verification passed").
        if (launch.isNotEmpty)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                agentRan ? Icons.check_circle : Icons.cancel,
                size: 15,
                color: agentRan ? OracleBrand.success : OracleBrand.error,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: SelectableText(
                  '${agentRan ? l10n.t('runs.agentOk') : l10n.t('runs.agentFail')} — $launch',
                  maxLines: 6,
                  style: TextStyle(
                    fontSize: 12,
                    color: agentRan ? OracleBrand.gray400 : OracleBrand.error,
                  ),
                ),
              ),
            ],
          ),
        // 2) The runner-enforced step requirement, when one failed.
        if (requirement.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.assignment_late_outlined,
                  size: 15,
                  color: OracleBrand.warning,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: SelectableText(
                    requirement,
                    style: const TextStyle(
                      fontSize: 12,
                      color: OracleBrand.warning,
                    ),
                  ),
                ),
              ],
            ),
          ),
        // 3) The verifier commands result (only meaningful once the step ended).
        if (!running)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              children: [
                Icon(
                  passed ? Icons.check_circle : Icons.cancel,
                  size: 15,
                  color: passed ? OracleBrand.success : OracleBrand.error,
                ),
                const SizedBox(width: 6),
                Text(
                  passed
                      ? l10n.t('runs.verifPassed')
                      : l10n.t('runs.verifFailed'),
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: passed ? OracleBrand.success : OracleBrand.error,
                  ),
                ),
              ],
            ),
          ),
        for (final (cmd, ok) in commandLines)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              children: [
                Icon(
                  ok ? Icons.check_circle_outline : Icons.highlight_off,
                  size: 14,
                  color: ok ? OracleBrand.success : OracleBrand.error,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    '\$ $cmd',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (outputLines.isNotEmpty) ...[
          const SizedBox(height: 8),
          _rawBox(outputLines.join('\n')),
        ],
      ],
    );
  }
}

/// The technical pane: ids + the raw payloads, for deep debugging.
class _TechView extends StatelessWidget {
  final FlowRunStepEntity iteration;
  const _TechView({required this.iteration});

  @override
  Widget build(BuildContext context) {
    final it = iteration;
    Widget row(String label, String value) => Padding(
      padding: const EdgeInsets.only(top: 2),
      child: SelectableText(
        '$label: $value',
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 11,
          color: OracleBrand.gray500,
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        row('runStepId', it.id.value),
        row('stepId', it.stepId.value),
        if (it.sessionId != null) row('sessionId', it.sessionId!.value),
        if (it.startedAt != null)
          row('startedAt', it.startedAt!.toIso8601String()),
        if (it.endedAt != null) row('endedAt', it.endedAt!.toIso8601String()),
        if ((it.report ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          _rawBox(_prettyJson(it.report!)),
        ],
        if ((it.verifier ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          _rawBox(_prettyJson(it.verifier!)),
        ],
      ],
    );
  }
}

/// One blackboard entry, key highlighted, value selectable.
class _BlackboardRow extends StatelessWidget {
  final FlowRunContextEntity entry;
  const _BlackboardRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final internal = entry.key.startsWith('_');
    final formatted = _prettyJson(entry.value);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: OracleBrand.gray900.withValues(alpha: .52),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: OracleBrand.gray700),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: Row(
              children: [
                Icon(
                  internal ? Icons.settings_outlined : Icons.data_object,
                  size: 19,
                  color: internal ? OracleBrand.gray500 : OracleBrand.violet,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(entry.key)),
                IconButton(
                  tooltip: l10n.t('runs.copy'),
                  icon: const Icon(Icons.copy, size: 17),
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: entry.value)),
                ),
              ],
            ),
            content: SizedBox(width: 680, child: _rawBox(formatted)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l10n.t('common.close')),
              ),
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (internal ? OracleBrand.gray500 : OracleBrand.violet)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  entry.key,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: internal
                        ? OracleBrand.gray400
                        : OracleBrand.violetSoft,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  formatted.replaceAll('\n', ' '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: OracleBrand.gray400,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              const Icon(
                Icons.open_in_full,
                size: 14,
                color: OracleBrand.gray500,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One timeline entry: localized kind + step key + compact readable payload.
class _EventRow extends StatelessWidget {
  final FlowRunEventEntity event;
  final Map<String, FlowStepEntity> defsById;
  const _EventRow({required this.event, required this.defsById});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 128,
            child: Text(
              fmtDateTime(event.createdAt),
              style: const TextStyle(fontSize: 11, color: OracleBrand.gray500),
            ),
          ),
          StatusBadge(eventKindLabel(event.kind), color: OracleBrand.gray500),
          const SizedBox(width: 10),
          Expanded(
            child: SelectableText(
              _compactPayload(event.payload),
              maxLines: 2,
              style: const TextStyle(
                fontSize: 11.5,
                color: OracleBrand.gray400,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _compactPayload(String payload) {
    try {
      final j = jsonDecode(payload);
      if (j is Map) {
        return j.entries.map((e) => '${e.key}: ${e.value}').join(' · ');
      }
    } catch (_) {
      /* raw */
    }
    return payload;
  }
}

// ── shared helpers ──

Widget _rawBox(String content) => Container(
  width: double.infinity,
  constraints: const BoxConstraints(maxHeight: 260),
  padding: const EdgeInsets.all(10),
  decoration: BoxDecoration(
    color: OracleBrand.gray950,
    borderRadius: BorderRadius.circular(8),
    border: Border.all(color: OracleBrand.gray700),
  ),
  child: SingleChildScrollView(
    child: SelectableText(
      content,
      style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5),
    ),
  ),
);

String? _fmtDuration(DateTime? start, DateTime? end) {
  if (start == null) return null;
  final d = (end ?? DateTime.now()).difference(start);
  if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes % 60}m';
  if (d.inMinutes > 0) return '${d.inMinutes}m ${d.inSeconds % 60}s';
  return '${d.inSeconds}s';
}

String _prettyJson(String raw) {
  try {
    return const JsonEncoder.withIndent('  ').convert(jsonDecode(raw));
  } catch (_) {
    return raw;
  }
}
