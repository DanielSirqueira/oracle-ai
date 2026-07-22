import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:oracle_core/oracle_core.dart';
import 'package:oracle_memory/oracle_memory.dart';

import 'flow_workspace.dart';
import 'agent_doctor.dart';
import 'managed_process.dart';
import 'prompt_composer.dart';
import 'step_launcher.dart';
import 'verifier.dart';

enum _Outcome { success, failure, gate, stalled }

class _StepResult {
  final _Outcome outcome;
  final String? verdict;
  const _StepResult(this.outcome, {this.verdict});
}

class _DurableRunState {
  final List<String> queue;
  String? activeStep;
  String? waiting;
  int visits;
  bool initialized;
  final Map<String, Set<String>> arrivals;

  _DurableRunState({
    List<String>? queue,
    this.activeStep,
    this.waiting,
    this.visits = 0,
    this.initialized = false,
    Map<String, Set<String>>? arrivals,
  }) : queue = queue ?? <String>[],
       arrivals = arrivals ?? <String, Set<String>>{};

  factory _DurableRunState.parse(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return _DurableRunState(
          queue: (decoded['queue'] as List? ?? const [])
              .map((e) => e.toString())
              .where((e) => e.isNotEmpty)
              .toList(),
          activeStep: decoded['activeStep']?.toString(),
          waiting: decoded['waiting']?.toString(),
          visits: (decoded['visits'] as num? ?? 0).toInt(),
          initialized: decoded['version'] == 1 || decoded['version'] == 2,
          arrivals: decoded['arrivals'] is Map
              ? {
                  for (final entry in (decoded['arrivals'] as Map).entries)
                    '${entry.key}': (entry.value as List? ?? const [])
                        .map((value) => '$value')
                        .toSet(),
                }
              : null,
        );
      }
    } catch (_) {
      // A corrupt checkpoint must not be treated as a valid empty frontier.
    }
    return _DurableRunState();
  }

  String encode() => jsonEncode({
    'version': 2,
    'queue': queue,
    'activeStep': activeStep,
    'waiting': waiting,
    'visits': visits,
    'arrivals': {
      for (final entry in arrivals.entries) entry.key: entry.value.toList(),
    },
  });
}

class _LeaseLost implements Exception {
  const _LeaseLost();
  @override
  String toString() => 'Flow worker lease lost';
}

/// The deterministic Flow Runner — the "n8n engine" for AI dev loops. It is NOT
/// an agent: it claims queued runs (lease + heartbeat), creates a git worktree,
/// walks the flow GRAPH, launches a headless coding agent per step, runs the
/// verifiers OUTSIDE the agent, and applies budgets, gates and transitions.
/// All state lives in the database, so a killed worker's run is resumable.
///
/// Graph traversal is a queue scheduler, so the canvas's free graphs execute:
/// fan-OUT (one step feeding several) runs each branch one after the other;
/// fan-IN (a join) waits until its queued predecessors have run; loop-backs
/// (verdict/failure edges pointing at earlier steps) re-execute them, protected
/// by the total step-visit budget and an anti-livelock breaker.
class FlowWorker {
  final FlowRepository _repo;
  final StepLauncher _launcher;
  final Verifier _verifier;
  final PromptComposer _composer;
  final FlowWorkspace _workspace;
  final CaptureRepository _capture;

  /// Language of the prompts handed to step agents ('pt' | 'en').
  final String language;

  FlowWorker({
    FlowRepository? repository,
    StepLauncher? launcher,
    Verifier? verifier,
    PromptComposer? composer,
    FlowWorkspace? workspace,
    CaptureRepository? captureRepository,
    this.language = 'pt',
  }) : _repo = repository ?? injector.get<FlowRepository>(),
       _launcher = launcher ?? StepLauncher(),
       _verifier = verifier ?? Verifier(),
       _composer = composer ?? PromptComposer(),
       _workspace = workspace ?? FlowWorkspace(),
       _capture = captureRepository ?? injector.get<CaptureRepository>();

  /// Runaway backstop: no run may execute more than this many step visits.
  static const _maxTotalStepVisits = 200;

  /// Max nesting for `subflow` steps (a child flow calling another child).
  static const _maxSubflowDepth = 3;

  /// Loops forever: claim runs and drive them, else idle. [parallel] lanes run
  /// concurrently — each lane claims its own run (`FOR UPDATE SKIP LOCKED`
  /// guarantees two lanes never grab the same one), so N processes execute at
  /// the same time. `oracle_ai flow-worker`.
  Future<void> serve(
    String workerId, {
    Duration idle = const Duration(seconds: 5),
    int parallel = 1,
  }) async {
    final lanes = parallel < 1 ? 1 : parallel;
    stderr.writeln(
      '[oracle] flow-worker "$workerId" polling for runs… (parallel: $lanes)',
    );
    Future<void> lane(String id) async {
      while (true) {
        final worked = await runOnce(id);
        if (!worked) await Future<void>.delayed(idle);
      }
    }

    await Future.wait([
      for (var i = 0; i < lanes; i++)
        lane(lanes == 1 ? workerId : '$workerId-${i + 1}'),
    ]);
  }

  /// Claims and drives at most one run. Returns false when the queue is empty.
  Future<bool> runOnce(String workerId) async {
    final run = await _repo.claimRun(workerId);
    if (run == null) return false;
    stderr.writeln('[oracle] flow-worker claimed run ${run.id.value}');
    try {
      await _drive(run, workerId);
    } on _LeaseLost {
      // Another control action or worker generation owns the run now. Never
      // overwrite its status with a stale worker's failure.
      stderr.writeln('[oracle] lease lost for run ${run.id.value}');
    } catch (e) {
      await _repo.updateRunStatus(
        run.id,
        FlowRunStatus.failed,
        error: '$e',
        expectedWorkerId: workerId,
        expectedLeaseEpoch: run.leaseEpoch,
        expectedStatuses: const {FlowRunStatus.running},
      );
      await _safeEvent(run.id, 'error', {'message': '$e'});
    }
    return true;
  }

  Future<void> _drive(
    FlowRunEntity run,
    String workerId, {
    int depth = 0,
    String? presetWorkdir,
  }) async {
    final graphResult = await _repo.getFlow(run.flowId);
    if (graphResult.isError()) {
      await _repo.updateRunStatus(
        run.id,
        FlowRunStatus.failed,
        error: 'flow definition not found',
      );
      return;
    }
    final graph = graphResult.getOrThrow();
    final stepsByKey = {for (final s in graph.steps) s.stepKey: s};
    final idToKey = {for (final s in graph.steps) s.id.value: s.stepKey};

    // Incoming-edge sources per step key — the fan-in wait signal.
    final incoming = <String, List<String>>{};
    for (final e in graph.edges) {
      final from = idToKey[e.fromStep.value];
      final to = idToKey[e.toStep.value];
      if (from == null || to == null) continue;
      (incoming[to] ??= []).add(from);
    }

    // Resolve the task once (for prompt context).
    TaskEntity? task;
    if (run.taskId != null) {
      final t = await _repo.getTask(run.taskId!);
      if (t.isSuccess()) task = t.getOrThrow();
    }

    // The project rules EVERY step agent must follow (best-effort, fetched once).
    var rules = const <RuleEntity>[];
    if (run.projectId != null) {
      try {
        final r = await injector.get<RulesForTaskUsecase>()(
          RulesForTaskQuery(projectId: run.projectId!, limit: 20),
        );
        if (r.isSuccess()) rules = r.getOrThrow();
      } catch (_) {
        /* prompt without rules */
      }
    }

    final state = _DurableRunState.parse(run.executionState);
    final queue = state.queue;

    Future<void> checkpoint({
      IdVO? currentStepId,
      bool clearCurrentStep = false,
      int addTokens = 0,
    }) async {
      final ok = await _repo.checkpointRun(
        run.id,
        workerId,
        run.leaseEpoch,
        executionState: state.encode(),
        currentStepId: currentStepId,
        clearCurrentStep: clearCurrentStep,
        addTokens: addTokens,
      );
      if (!ok) throw const _LeaseLost();
    }

    void enqueueTarget(String fromKey, String targetKey) {
      if (stepsByKey[targetKey]?.kind != FlowStepKind.join) {
        if (!queue.contains(targetKey)) queue.add(targetKey);
        return;
      }
      final arrived = state.arrivals.putIfAbsent(targetKey, () => <String>{});
      arrived.add(fromKey);
      final required = incoming[targetKey]?.toSet() ?? const <String>{};
      if (required.isNotEmpty && arrived.containsAll(required)) {
        state.arrivals.remove(targetKey);
        if (!queue.contains(targetKey)) queue.add(targetKey);
      }
    }

    // Resume vs fresh start. The repo root comes from the run's project (so a
    // worker hosted OUTSIDE the repo — e.g. by Oracle Studio — still operates in
    // the right tree), falling back to the current directory.
    final repoRoot = await _resolveRepoRoot(run);
    final requiredAgents = graph.steps
        .where((step) => step.agent != null && step.agent!.trim().isNotEmpty)
        .map((step) => step.agent!.trim())
        .toSet();
    for (final agent in requiredAgents) {
      final health = await AgentDoctor(repoRoot: repoRoot).check(agent);
      if (!health.ready) {
        final reason = !health.cli.ok
            ? 'Agent CLI not available: $agent (${health.cli.detail})'
            : 'Oracle MCP not configured for $agent (${health.mcp.detail})';
        await _repo.updateRunStatus(
          run.id,
          FlowRunStatus.failed,
          error: reason,
          expectedWorkerId: workerId,
          expectedLeaseEpoch: run.leaseEpoch,
          expectedStatuses: const {FlowRunStatus.running},
        );
        await _safeEvent(run.id, 'preflight_failed', {
          'agent': agent,
          'cli': health.cli.detail,
          'mcp': health.mcp.detail,
          'reason': reason,
        });
        if (task != null && depth == 0) {
          await _repo.updateTask(task.id, status: TaskStatus.blocked);
        }
        return;
      }
    }
    String workdir;
    if (state.initialized || run.currentStepId != null) {
      // Resuming (human gate approved, failed-step park approved, or an
      // orphaned run reclaimed after a worker died). Reuse the run's worktree
      // if it had one, else fall back to the repo root (so a run that ran in
      // place is NOT restarted from the entry).
      workdir = run.worktreePath ?? repoRoot;
      final gateKey =
          state.activeStep ??
          (run.currentStepId == null
              ? null
              : idToKey[run.currentStepId!.value]);
      final gateStep = gateKey == null ? null : stepsByKey[gateKey];
      if (gateStep != null) {
        if (state.waiting == 'human' ||
            (!state.initialized && gateStep.kind == FlowStepKind.humanGate)) {
          // A human APPROVED the gate — continue past it.
          final resumedEdges = _matchingEdges(graph, gateStep, true, null);
          for (final edge in resumedEdges) {
            final target = idToKey[edge.toStep.value];
            if (target == null) continue;
            await _event(run.id, 'route', {
              'edgeId': edge.id.value,
              'from': gateStep.stepKey,
              'to': target,
              'outcome': 'success',
              'condition': edge.condition,
              'resumed': true,
            });
            enqueueTarget(gateStep.stepKey, target);
          }
        } else {
          // Parked on failure/quota (or worker death): approving means RUN THE
          // STEP AGAIN — never silently skip work that didn't happen. To move
          // on WITHOUT it, the user forces a skip (the `_skip` control).
          queue.remove(gateStep.stepKey);
          queue.insert(0, gateStep.stepKey);
        }
      }
      state
        ..initialized = true
        ..activeStep = null
        ..waiting = null;
      await checkpoint(clearCurrentStep: true);
      await _event(run.id, 'state', {'resumed': true, 'from': gateKey});
    } else if (presetWorkdir != null) {
      // Child run of a `subflow` step: inherit the PARENT's workspace (one
      // writer per branch) — never open a second worktree for the same work.
      workdir = presetWorkdir;
      await _repo.updateRunStatus(
        run.id,
        FlowRunStatus.running,
        branchName: run.branchName,
        worktreePath: presetWorkdir,
      );
      await _event(run.id, 'state', {
        'workspace': 'inherited',
        'path': presetWorkdir,
        'depth': depth,
      });
      final entry = graph.flow.entryStepKey.isNotEmpty
          ? graph.flow.entryStepKey
          : (graph.steps.isEmpty ? null : graph.steps.first.stepKey);
      if (entry != null) queue.add(entry);
      state.initialized = true;
      await checkpoint(clearCurrentStep: true);
    } else {
      workdir = repoRoot;
      try {
        final ws = await _workspace.create(
          repoRoot: repoRoot,
          runId: run.id.value,
          slug: _slug(task, graph.flow),
        );
        workdir = ws.path;
        await _repo.updateRunStatus(
          run.id,
          FlowRunStatus.running,
          branchName: ws.branch,
          worktreePath: ws.path,
        );
        run = run.copyWith(branchName: ws.branch, worktreePath: ws.path);
        await _event(run.id, 'state', {
          'branch': ws.branch,
          'worktree': ws.path,
        });
      } on FlowWorkspaceException catch (e) {
        await _repo.updateRunStatus(
          run.id,
          FlowRunStatus.failed,
          error: e.message,
          expectedWorkerId: workerId,
          expectedLeaseEpoch: run.leaseEpoch,
          expectedStatuses: const {FlowRunStatus.running},
        );
        await _safeEvent(run.id, 'error', {
          'workspace': 'failed',
          'reason': e.message,
        });
        if (task != null && depth == 0) {
          await _repo.updateTask(task.id, status: TaskStatus.blocked);
        }
        return;
      }
      if (task != null && depth == 0) {
        await _repo.updateTask(task.id, status: TaskStatus.running);
      }
      final entry = graph.flow.entryStepKey.isNotEmpty
          ? graph.flow.entryStepKey
          : (graph.steps.isEmpty ? null : graph.steps.first.stepKey);
      if (entry != null) queue.add(entry);
      state.initialized = true;
      await checkpoint(clearCurrentStep: true);
    }

    var finalStatus = FlowRunStatus.completed;

    while (queue.isNotEmpty) {
      if (++state.visits > _maxTotalStepVisits) {
        finalStatus = FlowRunStatus.stalled;
        await _event(run.id, 'budget', {'reason': 'max step visits'});
        break;
      }

      // Cancel/pause is cooperative, and the token budget is enforced, at step
      // boundaries — using the run's live tokens_used (accumulated per step).
      final live = await _repo.getRun(run.id);
      if (live.isSuccess()) {
        final liveRun = live.getOrThrow().run;
        if (liveRun.status == FlowRunStatus.cancelled ||
            liveRun.status == FlowRunStatus.paused) {
          await _event(run.id, 'state', {'stopped': liveRun.status.code});
          return;
        }
        if (_overBudget(liveRun.budgets, liveRun.tokensUsed)) {
          finalStatus = FlowRunStatus.stalled;
          await _event(run.id, 'budget', {
            'reason': 'token budget',
            'tokensUsed': liveRun.tokensUsed,
          });
          break;
        }
        if (_overWallBudget(liveRun)) {
          finalStatus = FlowRunStatus.stalled;
          await _event(run.id, 'budget', {
            'reason': 'wall clock budget',
            'startedAt': liveRun.startedAt?.toIso8601String(),
          });
          break;
        }
      }
      if (!await _repo.heartbeatRun(run.id, workerId, run.leaseEpoch)) {
        throw const _LeaseLost();
      }

      // Join nodes enter the queue only after every incoming route records an
      // arrival, so ordinary steps can keep simple FIFO semantics.
      final currentKey = queue.removeAt(0);

      final step = stepsByKey[currentKey];
      if (step == null) {
        finalStatus = FlowRunStatus.failed;
        await _event(run.id, 'error', {'message': 'unknown step $currentKey'});
        break;
      }
      state
        ..activeStep = currentKey
        ..waiting = null;
      await checkpoint(currentStepId: step.id);

      // The verdict routes this step CAN take (its verdict-edges), each with
      // the author's INSTRUCTION of when to take it — handed to the step's
      // agent so ANY node with verdict connections is a decision point.
      final verdictOptions = <VerdictOption>[
        for (final e in graph.edges)
          if (e.fromStep.value == step.id.value &&
              e.condition == 'verdict' &&
              (e.verdictValue ?? '').isNotEmpty)
            (value: e.verdictValue!, instruction: e.instruction),
      ];
      // When the ONLY way forward is a verdict (no success/always fallback),
      // the runner REQUIRES the agent to write one — else the run would stall.
      final verdictRequired =
          verdictOptions.isNotEmpty &&
          !graph.edges.any(
            (e) =>
                e.fromStep.value == step.id.value &&
                (e.condition == 'success' || e.condition == 'always'),
          );

      // A user-forced SKIP (Studio's "Pular etapa"): don't launch anything —
      // record the step as skipped and follow the route the user picked.
      final skip = await _takeSkip(run, step.stepKey);
      // Keep the lease alive for the WHOLE step (agents/commands/child flows
      // may run for hours) — without this the run would look orphaned after
      // 5 minutes and another worker would reclaim it mid-step.
      var leaseLost = false;
      final lease = Timer.periodic(
        const Duration(seconds: 60),
        (_) => unawaited(() async {
          if (!await _repo.heartbeatRun(run.id, workerId, run.leaseEpoch)) {
            leaseLost = true;
          }
        }()),
      );
      final _StepResult result;
      try {
        result = skip.requested
            ? await _skipStep(run, step, skip.verdict)
            : await _runStep(
                run,
                step,
                workdir,
                task,
                rules,
                verdictOptions,
                verdictRequired,
                workerId,
                depth,
              );
      } finally {
        lease.cancel();
      }
      if (leaseLost ||
          !await _repo.heartbeatRun(run.id, workerId, run.leaseEpoch)) {
        throw const _LeaseLost();
      }

      if (result.outcome == _Outcome.gate) {
        state.waiting = step.kind == FlowStepKind.humanGate ? 'human' : 'retry';
        await checkpoint(currentStepId: step.id);
        await _repo.updateRunStatus(
          run.id,
          FlowRunStatus.awaitingHuman,
          currentStepId: step.id,
          expectedWorkerId: workerId,
          expectedLeaseEpoch: run.leaseEpoch,
          expectedStatuses: const {FlowRunStatus.running},
        );
        await _event(run.id, 'gate', {
          'step': currentKey,
          'pendingBranches': queue.length,
        });
        return; // resumed by oracle_flow_gate_decide
      }
      if (result.outcome == _Outcome.stalled) {
        finalStatus = FlowRunStatus.stalled;
        break;
      }

      // A pause/cancel arriving during the step wins over its late result.
      if (!await _repo.heartbeatRun(run.id, workerId, run.leaseEpoch)) {
        throw const _LeaseLost();
      }

      final passed = result.outcome == _Outcome.success;
      final matchedEdges = _matchingEdges(graph, step, passed, result.verdict);
      final targets = <String>[
        for (final edge in matchedEdges)
          if (idToKey[edge.toStep.value] case final target?) target,
      ];
      if (!passed && targets.isEmpty) {
        finalStatus = FlowRunStatus.failed;
        await _event(run.id, 'route_error', {
          'step': step.stepKey,
          'reason': 'no failure route',
        });
        break;
      }
      final outgoing = graph.edges.any(
        (edge) => edge.fromStep.value == step.id.value,
      );
      if (passed && outgoing && targets.isEmpty) {
        finalStatus = FlowRunStatus.failed;
        await _event(run.id, 'route_error', {
          'step': step.stepKey,
          'reason': result.verdict == null
              ? 'no matching success route'
              : 'no route for verdict "${result.verdict}"',
        });
        break;
      }
      for (final edge in matchedEdges) {
        final target = idToKey[edge.toStep.value];
        if (target == null) continue;
        await _event(run.id, 'route', {
          'edgeId': edge.id.value,
          'from': step.stepKey,
          'to': target,
          'outcome': passed ? 'success' : 'failure',
          'condition': edge.condition,
          if (result.verdict != null) 'verdict': result.verdict,
        });
        enqueueTarget(step.stepKey, target);
      }
      state
        ..activeStep = null
        ..waiting = null;
      await checkpoint(clearCurrentStep: true);
    }

    if (finalStatus == FlowRunStatus.completed && state.arrivals.isNotEmpty) {
      finalStatus = FlowRunStatus.stalled;
      await _event(run.id, 'join_waiting', {
        'reason': 'not all configured incoming branches reached their join',
        'joins': {
          for (final entry in state.arrivals.entries)
            entry.key: {
              'arrived': entry.value.toList(),
              'required': incoming[entry.key] ?? const <String>[],
            },
        },
      });
    }

    // A child run must never touch the shared TASK status — that is the parent's.
    await _finalize(
      run,
      depth == 0 ? task : null,
      finalStatus,
      workerId: workerId,
    );
  }

  Future<_StepResult> _runStep(
    FlowRunEntity run,
    FlowStepEntity step,
    String workdir,
    TaskEntity? task,
    List<RuleEntity> rules,
    List<VerdictOption> verdictOptions,
    bool verdictRequired,
    String workerId,
    int depth,
  ) async {
    if (step.kind == FlowStepKind.humanGate) {
      return const _StepResult(_Outcome.gate);
    }

    if (step.kind == FlowStepKind.command) {
      return _runCommandStep(run, step, workdir, workerId);
    }

    if (step.kind == FlowStepKind.subflow) {
      return _runSubflow(run, step, workdir, workerId, depth);
    }

    if (step.kind == FlowStepKind.join) {
      return _runJoinStep(run, step);
    }

    if (step.kind == FlowStepKind.rfcGate) {
      return _runRfcGate(run, step);
    }

    // Precondition: review/consolidate need the RFC to EXIST (rfc_id on the
    // blackboard). Fail fast with the exact reason instead of launching an
    // agent that has nothing to review.
    if (step.kind == FlowStepKind.rfcReview ||
        step.kind == FlowStepKind.rfcConsolidate) {
      final pre = await _requireBlackboard(run, 'rfc_id');
      if (!pre) {
        final t = language == 'en' ? _reqEn : _reqPt;
        final startResult = await _repo.startRunStep(
          FlowRunStepEntity(
            id: const IdVO.empty(),
            runId: run.id,
            stepId: step.id,
            iteration: 1,
            status: FlowRunStepStatus.running,
            claimToken: _claimToken(run),
            agent: step.agent,
          ),
        );
        if (startResult.isSuccess()) {
          await _repo.updateRunStep(
            startResult.getOrThrow().copyWith(
              status: FlowRunStepStatus.failed,
              verifier: jsonEncode({
                'passed': false,
                'requirement': t['rfc_id_pre'],
              }),
            ),
          );
        }
        await _event(run.id, 'error', {
          'step': step.stepKey,
          'message': 'rfc_id missing (precondition)',
        });
        return switch (step.onFail) {
          'continue' => const _StepResult(_Outcome.success),
          'halt' => const _StepResult(_Outcome.failure),
          _ => const _StepResult(_Outcome.gate),
        };
      }
    }

    // Agent / orchestrator / decision / rfc_* — the inner loop. Iteration
    // numbering CONTINUES across visits (a loop-back re-executes the step, and
    // (run, step, iteration) is unique in the database).
    final baseIteration = await _nextIterationBase(run, step.id);
    var agentSessionId = await _latestAgentSessionId(run, step.id);
    String? feedback;
    var visitTokens = 0;
    for (var attempt = 1; attempt <= step.maxIterations; attempt++) {
      final iteration = baseIteration + attempt;
      final startResult = await _repo.startRunStep(
        FlowRunStepEntity(
          id: const IdVO.empty(),
          runId: run.id,
          stepId: step.id,
          iteration: iteration,
          status: FlowRunStepStatus.running,
          claimToken: _claimToken(run),
          agent: step.agent,
        ),
      );
      if (startResult.isError()) return const _StepResult(_Outcome.failure);
      var runStep = startResult.getOrThrow();

      // Inline the run's live state (blackboard, prior reports, artifacts) into
      // the prompt so the agent starts oriented even before its first tool call.
      final ctxResult = await _repo.stepContext(runStep.id);
      final stepCtx = ctxResult.isSuccess() ? ctxResult.getOrThrow() : null;

      final prompt = _composer.compose(
        run: run,
        step: step,
        runStepId: runStep.id,
        // Inlined into the protocol section: agent hosts that do NOT inherit
        // the worker's environment into their MCP server process (Codex) have
        // no other way to present a valid token to oracle_flow_step_report.
        claimToken: runStep.claimToken ?? _claimToken(run),
        iteration: attempt, // retry count WITHIN this visit
        task: task,
        context: stepCtx,
        rules: rules,
        verdictOptions: verdictOptions,
        verifierFeedback: feedback,
        language: language,
      );
      await _event(run.id, 'iteration', {
        'step': step.stepKey,
        'iteration': iteration,
        'agent': step.agent,
      });

      // LIVE observability: persist the prompt + planned command BEFORE the
      // agent starts, so the monitor shows them while the step is running —
      // not only after the run finishes.
      final agentName = step.agent ?? run.startedBy;
      final effort = _configString(step.config, 'reasoningEffort');
      // Optional per-step override of the Codex sandbox mode (config key
      // `codexSandbox`: read-only | workspace-write | danger-full-access).
      final codexSandbox = _configString(step.config, 'codexSandbox');
      // Claude and Gemini accept a caller-selected id for their first turn.
      // Codex and Cursor allocate one and expose it in structured output.
      final newAgentSessionId =
          agentSessionId == null && StepLauncher.canAssignSessionId(agentName)
          ? runStep.id.value
          : null;
      final preview = _launcher.previewCommand(
        agent: agentName,
        model: step.model,
        effort: effort,
        workdir: workdir,
        permissionsJson: step.permissions,
        resumeSessionId: agentSessionId,
        newSessionId: newAgentSessionId,
        codexSandbox: codexSandbox,
      );

      // One logical node owns one Oracle transcript. Every iteration opens a
      // new request inside it while the native agent conversation is resumed.
      // The transcript exists BEFORE launch, so live monitoring never depends
      // on a hook race or on a CLI exposing its private session id.
      final sessionProjectId = run.projectId;
      if (sessionProjectId == null) {
        await _repo.updateRunStep(
          runStep.copyWith(
            status: FlowRunStepStatus.failed,
            renderedPrompt: prompt,
            verifier: jsonEncode({
              'session': 'failed',
              'error': 'A project is required to create an agent session',
            }),
          ),
        );
        return const _StepResult(_Outcome.failure);
      }
      final sessionResult = await _capture.startSession(
        SessionEntity(
          id: const IdVO.empty(),
          projectId: sessionProjectId,
          agent: agentName,
          externalId: 'flow:${run.id.value}:${step.id.value}',
          cwd: workdir,
        ),
      );
      if (sessionResult.isError()) {
        await _repo.updateRunStep(
          runStep.copyWith(
            status: FlowRunStepStatus.failed,
            renderedPrompt: prompt,
            verifier: jsonEncode({
              'session': 'failed',
              'error': sessionResult.exceptionOrNull()!.errorMessage,
            }),
          ),
        );
        return const _StepResult(_Outcome.failure);
      }
      final session = sessionResult.getOrThrow();
      final requestResult = await _capture.openRequest(
        RequestEntity(
          id: const IdVO.empty(),
          sessionId: session.id,
          userText: TextVO(prompt),
        ),
      );
      if (requestResult.isError()) {
        await _repo.updateRunStep(
          runStep.copyWith(
            status: FlowRunStepStatus.failed,
            sessionId: session.id,
            renderedPrompt: prompt,
            verifier: jsonEncode({
              'session': 'request_failed',
              'error': requestResult.exceptionOrNull()!.errorMessage,
            }),
          ),
        );
        return const _StepResult(_Outcome.failure);
      }
      final request = requestResult.getOrThrow();
      final linkedResult = await _repo.updateRunStep(
        runStep.copyWith(
          sessionId: session.id,
          agentSessionId: agentSessionId ?? newAgentSessionId,
          renderedPrompt: prompt,
          verifier: jsonEncode({
            if (preview.isNotEmpty) 'command': preview,
            'running': true,
          }),
        ),
      );
      if (linkedResult.isError()) return const _StepResult(_Outcome.failure);
      runStep = linkedResult.getOrThrow();

      StepLaunchResult? launched;
      var launchDetails = '';
      try {
        launched = await _launcher.launch(
          agent: agentName,
          model: step.model,
          effort: effort,
          prompt: prompt,
          workdir: workdir,
          timeoutMinutes: step.timeoutMinutes,
          environment: _agentEnv(run, runStep),
          isCancelled: () async =>
              !await _repo.heartbeatRun(run.id, workerId, run.leaseEpoch),
          permissionsJson: step.permissions,
          resumeSessionId: agentSessionId,
          newSessionId: newAgentSessionId,
          codexSandbox: codexSandbox,
        );
        launchDetails = launched.timedOut
            ? 'agent timed out after ${step.timeoutMinutes}m'
            : 'agent exit ${launched.exitCode}';
        // On failure, surface WHY: the CLI's stderr (or stdout) tail carries the
        // real error — invalid model, auth, missing MCP, etc.
        if (!launched.ok) {
          final why = launched.stderr.trim().isNotEmpty
              ? launched.stderr.trim()
              : launched.stdout.trim();
          if (why.isNotEmpty) launchDetails = '$launchDetails\n${_clip(why)}';
        }
      } on StepLauncherException catch (e) {
        launchDetails = e.message;
      }
      final launchOk = launched?.ok ?? false;
      final agentSessionTotalTokens = launched?.tokensUsed ?? 0;
      var iterTokens = agentSessionTotalTokens;

      // Persist the external conversation identity immediately. For named
      // sessions the requested id is authoritative after a successful launch;
      // for Codex/Cursor it comes from the structured output. If a resumed CLI
      // reports a different id (for example after an upstream fork), follow the
      // reported id and record the transition instead of losing continuity.
      final observedSessionId = launched?.sessionExternalId?.trim();
      final previousAgentSessionId = agentSessionId;
      final resolvedAgentSessionId = observedSessionId?.isNotEmpty == true
          ? observedSessionId
          : (launchOk ? newAgentSessionId : agentSessionId);
      // Codex reports cumulative usage for a resumed thread. Persist the raw
      // session total for the next turn, but charge/show only this iteration's
      // delta; otherwise every retry counts the whole conversation again.
      if (agentName == 'codex' &&
          previousAgentSessionId != null &&
          agentSessionTotalTokens > 0) {
        final previousTotal = await _latestAgentSessionTotalTokens(
          run,
          step.id,
          previousAgentSessionId,
        );
        if (previousTotal > 0 && agentSessionTotalTokens >= previousTotal) {
          iterTokens = agentSessionTotalTokens - previousTotal;
        }
      }
      visitTokens += iterTokens;
      if (resolvedAgentSessionId != null && resolvedAgentSessionId.isNotEmpty) {
        agentSessionId = resolvedAgentSessionId;
        // The agent may have called oracle_flow_step_report while its process
        // was running. Re-read before writing the native id so that report is
        // never overwritten by this worker's older in-memory snapshot.
        final currentResult = await _repo.getRunStep(runStep.id);
        final current = currentResult.isSuccess()
            ? currentResult.getOrThrow()
            : runStep;
        final persistedResult = await _repo.updateRunStep(
          current.copyWith(agentSessionId: agentSessionId),
        );
        if (persistedResult.isSuccess()) runStep = persistedResult.getOrThrow();
        if (previousAgentSessionId != null &&
            previousAgentSessionId != agentSessionId) {
          await _event(run.id, 'agent_session', {
            'step': step.stepKey,
            'previous': previousAgentSessionId,
            'current': agentSessionId,
            'reason': 'agent_reported_different_session',
          });
        }
      }

      // Persist what the agent did in the guaranteed execution session. Hooks
      // may capture more granular activity, but this request/answer pair is the
      // stable minimum available to the run monitor for every supported CLI.
      final answer = (launched?.resultText ?? '').trim();
      final fallback = launched == null
          ? launchDetails
          : (launched.stdout.trim().isNotEmpty
                ? _clip(launched.stdout.trim())
                : launchDetails);
      await _capture.appendMessage(
        MessageEntity(
          id: const IdVO.empty(),
          requestId: request.id,
          role: launched?.ok == true
              ? MessageRole.assistant
              : MessageRole.system,
          content: TextVO(answer.isNotEmpty ? answer : fallback),
          tokenCount: iterTokens > 0 ? iterTokens : null,
        ),
      );
      if (iterTokens > 0) {
        await _capture.addSessionTokens(session.id, output: iterTokens);
      }
      if (iterTokens > 0) {
        await _repo.updateRunStatus(
          run.id,
          FlowRunStatus.running,
          addTokens: iterTokens,
          expectedWorkerId: workerId,
          expectedLeaseEpoch: run.leaseEpoch,
          expectedStatuses: const {FlowRunStatus.running},
        );
      }

      // Re-read the run-step to honor what the agent reported (this also
      // PRESERVES the agent's step_report instead of overwriting it): a
      // "blocked" report parks the run for a human instead of advancing.
      final reread = await _repo.getRunStep(runStep.id);
      final reported = reread.isSuccess() ? reread.getOrThrow() : runStep;
      if (reported.status == FlowRunStepStatus.parked) {
        await _repo.updateRunStep(
          reported.copyWith(
            renderedPrompt: prompt,
            sessionId: session.id,
            agentSessionId: agentSessionId,
            tokensUsed: iterTokens,
          ),
        );
        await _event(run.id, 'step_end', {
          'step': step.stepKey,
          'iteration': iteration,
          'blocked': true,
        });
        return const _StepResult(_Outcome.gate);
      }

      final verifier = await _verifier.run(
        exitCriteriaJson: step.exitCriteria,
        workdir: workdir,
        timeoutMinutes: _configInt(step.config, 'verifierTimeoutMinutes') ?? 15,
        isCancelled: () async =>
            !await _repo.heartbeatRun(run.id, workerId, run.leaseEpoch),
      );
      var passed = launchOk && verifier.passed;

      // Kind requirements, enforced BY THE RUNNER: an agent step must have
      // reported (proves the MCP protocol worked), an orchestrator must have
      // written the plan, an rfc_create must have written rfc_id, etc. Without
      // this, a step could "pass" silently having produced NOTHING — which is
      // exactly how a later step ends up missing its context.
      String? requirement;
      if (passed &&
          step.tokenBudget != null &&
          step.tokenBudget! > 0 &&
          visitTokens > step.tokenBudget!) {
        requirement =
            'Step token budget exceeded: $visitTokens > ${step.tokenBudget}';
        passed = false;
      }
      if (passed) {
        requirement = await _kindRequirement(
          run,
          step,
          reported,
          verdictRequired: verdictRequired,
        );
        if (requirement != null) passed = false;
      }
      if (passed) {
        requirement = _validateOutputSchema(step.outputSchema, reported.report);
        if (requirement != null) passed = false;
      }

      await _repo.updateRunStep(
        reported.copyWith(
          status: passed ? FlowRunStepStatus.passed : FlowRunStepStatus.failed,
          renderedPrompt: prompt,
          sessionId: session.id,
          agentSessionId: agentSessionId,
          tokensUsed: iterTokens,
          verifier: jsonEncode({
            if ((launched?.commandLine ?? '').isNotEmpty)
              'command': launched!.commandLine,
            'launch': launchDetails,
            'passed': verifier.passed,
            if (agentSessionTotalTokens > 0)
              'agentSessionTotalTokens': agentSessionTotalTokens,
            if (requirement != null) 'requirement': requirement,
            'details': verifier.details,
          }),
        ),
      );

      if (passed) {
        String? verdict;
        // ANY agent node with verdict connections is a decision point — the
        // dedicated decision kind is just the lightweight evaluator variant.
        if (verdictOptions.isNotEmpty ||
            step.kind == FlowStepKind.orchestrator ||
            step.kind == FlowStepKind.decision) {
          verdict = await _readVerdict(run.id, updatedBy: runStep.id);
          // CONSUME it — a stale verdict must never route a later step.
          if (verdict != null) {
            await _repo.putContext(
              FlowRunContextEntity(
                runId: run.id,
                key: 'verdict',
                value: '""',
                updatedBy: runStep.id,
              ),
            );
          }
        }
        return _StepResult(_Outcome.success, verdict: verdict);
      }

      // A retry without the native id would silently create a fresh agent
      // conversation and force it to rediscover the project. Stop visibly
      // instead; the transcript and failure remain available for diagnosis.
      if (attempt < step.maxIterations && agentSessionId == null) {
        await _event(run.id, 'agent_session', {
          'step': step.stepKey,
          'iteration': iteration,
          'missing': true,
          'message':
              'The agent did not expose a resumable session id; retry was parked to avoid losing context.',
        });
        return const _StepResult(_Outcome.gate);
      }

      // The agent's plan/credit ran out (rate limit, quota, no credit): retrying
      // now only burns MORE attempts against a wall. Park for a human; resuming
      // later RE-RUNS this step from where the run stands.
      if (!launchOk &&
          _isQuotaFailure(
            '${launched?.stderr ?? ''}\n${launched?.stdout ?? ''}'
            '\n$launchDetails',
          )) {
        await _event(run.id, 'budget', {
          'step': step.stepKey,
          'reason': 'agent_quota',
          'detail': _clip(launchDetails, 300),
        });
        return const _StepResult(_Outcome.gate);
      }

      final t = language == 'en' ? _reqEn : _reqPt;
      final protocolOnly = launchOk && verifier.passed && requirement != null;
      if (protocolOnly && _isMcpConnectorCancellation(answer)) {
        // Another turn in the same headless host will be cancelled at the same
        // boundary. Preserve the session and park once instead of consuming
        // every iteration with a misleading missing-report retry.
        await _event(run.id, 'integration_error', {
          'step': step.stepKey,
          'iteration': iteration,
          'code': 'mcp_call_cancelled_by_host',
          'message': t['connectorCancelled']!,
        });
        return const _StepResult(_Outcome.gate);
      }
      if (protocolOnly) {
        // The WORK is done — only the MCP protocol calls are missing. Tell the
        // retry to NOT redo anything and hand it the previous result so the
        // report can be written from it (no more full re-reviews per retry).
        final prior = _clip(launched?.resultText ?? '', 6000);
        feedback = [
          t['protocolOnly']!,
          requirement,
          if (prior.isNotEmpty) '${t['protocolOnlyPrior']}\n$prior',
        ].join('\n\n');
      } else {
        feedback = [
          launchDetails,
          if (requirement != null) requirement,
          verifier.details,
        ].join('\n');
      }

      // A user-forced skip issued while this attempt ran takes effect NOW —
      // no further retries.
      final skip = await _takeSkip(run, step.stepKey);
      if (skip.requested) {
        await _event(run.id, 'state', {
          'step': step.stepKey,
          'skipped': true,
          'forced': true,
        });
        return _StepResult(_Outcome.success, verdict: skip.verdict);
      }
    }

    // Inner loop exhausted — apply on_fail.
    await _event(run.id, 'budget', {
      'step': step.stepKey,
      'reason': 'max iterations',
      'onFail': step.onFail,
    });
    return switch (step.onFail) {
      'continue' => const _StepResult(_Outcome.success),
      'park' => const _StepResult(_Outcome.gate),
      _ => const _StepResult(_Outcome.failure),
    };
  }

  Future<_StepResult> _runCommandStep(
    FlowRunEntity run,
    FlowStepEntity step,
    String workdir,
    String workerId,
  ) async {
    final startResult = await _repo.startRunStep(
      FlowRunStepEntity(
        id: const IdVO.empty(),
        runId: run.id,
        stepId: step.id,
        iteration: await _nextIterationBase(run, step.id) + 1,
        status: FlowRunStepStatus.running,
        claimToken: _claimToken(run),
      ),
    );
    if (startResult.isError()) return const _StepResult(_Outcome.failure);
    var runStep = startResult.getOrThrow();

    var passed = true;
    var details = 'no command';
    final command = step.command;
    if (command != null && command.trim().isNotEmpty) {
      final result = await ManagedProcess.run(
        command,
        const [],
        workdir: workdir,
        runInShell: true,
        timeout: step.timeoutMinutes > 0
            ? Duration(minutes: step.timeoutMinutes)
            : null,
        isCancelled: () async =>
            !await _repo.heartbeatRun(run.id, workerId, run.leaseEpoch),
      );
      passed = result.exitCode == 0;
      details = result.timedOut
          ? 'timed out after ${step.timeoutMinutes}m'
          : result.cancelled
          ? 'cancelled'
          : 'exit ${result.exitCode}';
      if (result.stdout.trim().isNotEmpty) {
        details = '$details\nstdout:\n${_clip(result.stdout.trim(), 4000)}';
      }
      if (result.stderr.trim().isNotEmpty) {
        details = '$details\nstderr:\n${_clip(result.stderr.trim(), 4000)}';
      }
    }
    if (passed) {
      final verifier = await _verifier.run(
        exitCriteriaJson: step.exitCriteria,
        workdir: workdir,
        timeoutMinutes: _configInt(step.config, 'verifierTimeoutMinutes') ?? 15,
        isCancelled: () async =>
            !await _repo.heartbeatRun(run.id, workerId, run.leaseEpoch),
      );
      passed = verifier.passed;
      details = '$details; verifier ${verifier.passed}';
    }

    runStep = runStep.copyWith(
      status: passed ? FlowRunStepStatus.passed : FlowRunStepStatus.failed,
      verifier: jsonEncode({
        if (command != null && command.trim().isNotEmpty) 'command': command,
        'passed': passed,
        'details': details,
      }),
    );
    await _repo.updateRunStep(runStep);
    if (passed) return const _StepResult(_Outcome.success);
    return switch (step.onFail) {
      'continue' => const _StepResult(_Outcome.success),
      'park' => const _StepResult(_Outcome.gate),
      _ => const _StepResult(_Outcome.failure),
    };
  }

  /// Records the explicit synchronization barrier. Queue scheduling has
  /// already waited for every active incoming branch before this method is
  /// reached; the persisted step makes that zero-cost fan-in visible in the
  /// run monitor and audit trail.
  Future<_StepResult> _runJoinStep(
    FlowRunEntity run,
    FlowStepEntity step,
  ) async {
    final startResult = await _repo.startRunStep(
      FlowRunStepEntity(
        id: const IdVO.empty(),
        runId: run.id,
        stepId: step.id,
        iteration: await _nextIterationBase(run, step.id) + 1,
        status: FlowRunStepStatus.running,
        claimToken: _claimToken(run),
      ),
    );
    if (startResult.isError()) return const _StepResult(_Outcome.failure);
    await _repo.updateRunStep(
      startResult.getOrThrow().copyWith(
        status: FlowRunStepStatus.passed,
        verifier: jsonEncode({
          'passed': true,
          'join': true,
          'details': 'all active incoming branches completed',
        }),
      ),
    );
    await _event(run.id, 'info', {'step': step.stepKey, 'join': 'completed'});
    return const _StepResult(_Outcome.success);
  }

  /// Executes ANOTHER flow as a CHILD run, inline (n8n's "Execute Workflow"):
  /// resolves `config.flowKey`, copies the parent's blackboard down, drives the
  /// child in the SAME workspace (one writer per branch — never a second
  /// worktree), then merges the child's blackboard back up so later parent
  /// steps see what the sub-process produced. Depth-capped at
  /// [_maxSubflowDepth] to stop recursion bombs (a flow calling itself).
  Future<_StepResult> _runSubflow(
    FlowRunEntity run,
    FlowStepEntity step,
    String workdir,
    String workerId,
    int depth,
  ) async {
    final startResult = await _repo.startRunStep(
      FlowRunStepEntity(
        id: const IdVO.empty(),
        runId: run.id,
        stepId: step.id,
        iteration: await _nextIterationBase(run, step.id) + 1,
        status: FlowRunStepStatus.running,
        claimToken: _claimToken(run),
      ),
    );
    if (startResult.isError()) return const _StepResult(_Outcome.failure);
    final runStep = startResult.getOrThrow();
    final t = language == 'en' ? _reqEn : _reqPt;
    final flowKey = _configString(step.config, 'flowKey') ?? '';

    Future<_StepResult> fail(String message, {String? childRunId}) async {
      await _repo.updateRunStep(
        runStep.copyWith(
          status: FlowRunStepStatus.failed,
          verifier: jsonEncode({
            'passed': false,
            'subflow': flowKey,
            if (childRunId != null) 'childRunId': childRunId,
            'details': message,
          }),
        ),
      );
      await _event(run.id, 'error', {'step': step.stepKey, 'message': message});
      return switch (step.onFail) {
        'continue' => const _StepResult(_Outcome.success),
        'halt' => const _StepResult(_Outcome.failure),
        _ => const _StepResult(_Outcome.gate),
      };
    }

    if (depth >= _maxSubflowDepth) return fail(t['subflow_depth']!);
    if (flowKey.isEmpty) return fail(t['subflow_key']!);

    final target = await _repo.getFlowByKey(
      projectId: run.projectId,
      key: flowKey,
    );
    if (target.isError()) return fail('${t['subflow_missing']}: "$flowKey"');
    final graph = target.getOrThrow();

    final parentBundle = await _repo.getRun(run.id);
    final childKey = '_subflow:${step.stepKey}';
    FlowRunEntity? child;
    var newChild = false;
    if (parentBundle.isSuccess()) {
      for (final context in parentBundle.getOrThrow().context) {
        if (context.key != childKey) continue;
        try {
          final childId = jsonDecode(context.value)?.toString();
          if (childId == null || childId.isEmpty) continue;
          final existing = await _repo.getRun(IdVO(childId));
          if (existing.isError()) continue;
          final existingRun = existing.getOrThrow().run;
          child = existingRun.status == FlowRunStatus.completed
              ? existingRun
              : await _repo.claimChildRun(existingRun.id, workerId);
        } catch (_) {
          // A malformed legacy pointer is replaced by a new child below.
        }
      }
    }

    // Create the child already owned by this worker. It is excluded from the
    // global queue and can be explicitly re-adopted by a resumed parent.
    if (child == null) {
      final childResult = await _repo.startRun(
        FlowRunEntity(
          id: const IdVO.empty(),
          flowId: graph.flow.id,
          taskId: run.taskId,
          projectId: run.projectId,
          status: FlowRunStatus.running,
          budgets: run.budgets,
          startedBy: run.startedBy,
          claimedBy: workerId,
          leaseEpoch: 1,
          parentRunId: run.id,
        ),
      );
      if (childResult.isError()) return fail('${t['subflow_missing']}: run');
      child = childResult.getOrThrow().copyWith(
        branchName: run.branchName,
        worktreePath: run.worktreePath,
      );
      newChild = true;
      await _repo.putContext(
        FlowRunContextEntity(
          runId: run.id,
          key: childKey,
          value: jsonEncode(child.id.value),
          updatedBy: runStep.id,
        ),
      );
    }

    // Blackboard flows DOWN only once: resuming must not overwrite child state
    // that was produced before the parent worker stopped.
    if (newChild && parentBundle.isSuccess()) {
      for (final c in parentBundle.getOrThrow().context) {
        if (c.key == 'verdict' || c.key.startsWith('_')) continue;
        await _repo.putContext(
          FlowRunContextEntity(
            runId: child.id,
            key: c.key,
            value: c.value,
            updatedBy: runStep.id,
          ),
        );
      }
    }

    if (newChild) {
      await _repo.addArtifact(
        FlowArtifactEntity(
          id: const IdVO.empty(),
          runId: run.id,
          runStepId: runStep.id,
          kind: 'run',
          locator: child.id.value,
          meta: jsonEncode({'flowKey': flowKey, 'depth': depth + 1}),
        ),
      );
    }
    await _event(run.id, 'info', {
      'step': step.stepKey,
      'subflow': flowKey,
      'childRunId': child.id.value,
    });

    try {
      if (child.status != FlowRunStatus.completed) {
        await _drive(child, workerId, depth: depth + 1, presetWorkdir: workdir);
      }
    } on _LeaseLost {
      rethrow;
    } catch (e) {
      await _repo.updateRunStatus(
        child.id,
        FlowRunStatus.failed,
        error: '$e',
        expectedWorkerId: workerId,
        expectedLeaseEpoch: child.leaseEpoch,
        expectedStatuses: const {FlowRunStatus.running},
      );
    }

    final after = await _repo.getRun(child.id);
    final childStatus = after.isSuccess()
        ? after.getOrThrow().run.status
        : FlowRunStatus.failed;
    if (after.isSuccess()) {
      final accountedKey = '_subflow_accounted:${step.stepKey}';
      final alreadyAccounted =
          parentBundle.isSuccess() &&
          parentBundle.getOrThrow().context.any(
            (context) =>
                context.key == accountedKey &&
                context.value.contains(child!.id.value),
          );
      if (!alreadyAccounted && after.getOrThrow().run.tokensUsed > 0) {
        await _repo.updateRunStatus(
          run.id,
          FlowRunStatus.running,
          addTokens: after.getOrThrow().run.tokensUsed,
          expectedWorkerId: workerId,
          expectedLeaseEpoch: run.leaseEpoch,
          expectedStatuses: const {FlowRunStatus.running},
        );
        await _repo.putContext(
          FlowRunContextEntity(
            runId: run.id,
            key: accountedKey,
            value: jsonEncode(child.id.value),
            updatedBy: runStep.id,
          ),
        );
      }
    }
    if (childStatus != FlowRunStatus.completed) {
      return fail(
        '${t['subflow_failed']} (${childStatus.code})',
        childRunId: child.id.value,
      );
    }

    // Blackboard flows back UP: the child's outputs are this step's outputs.
    if (after.isSuccess()) {
      for (final c in after.getOrThrow().context) {
        if (c.key == 'verdict' || c.key.startsWith('_')) continue;
        await _repo.putContext(
          FlowRunContextEntity(
            runId: run.id,
            key: c.key,
            value: c.value,
            updatedBy: runStep.id,
          ),
        );
      }
    }
    await _repo.updateRunStep(
      runStep.copyWith(
        status: FlowRunStepStatus.passed,
        verifier: jsonEncode({
          'passed': true,
          'subflow': flowKey,
          'childRunId': child.id.value,
          'childStatus': childStatus.code,
        }),
      ),
    );
    return const _StepResult(_Outcome.success);
  }

  /// The runner-enforced deliverable of each agent-step kind. Returns the
  /// feedback message (in the run's language) when unmet — the iteration FAILS
  /// and retries with this message in the prompt, instead of passing empty.
  Future<String?> _kindRequirement(
    FlowRunEntity run,
    FlowStepEntity step,
    FlowRunStepEntity reported, {
    bool verdictRequired = false,
  }) async {
    const agentKinds = {
      FlowStepKind.agent,
      FlowStepKind.orchestrator,
      FlowStepKind.decision,
      FlowStepKind.rfcCreate,
      FlowStepKind.rfcReview,
      FlowStepKind.rfcConsolidate,
    };
    if (!agentKinds.contains(step.kind)) return null;
    final t = language == 'en' ? _reqEn : _reqPt;

    // 1) The step MUST have reported — the proof the MCP protocol worked at all.
    if ((reported.report ?? '').trim().isEmpty) return t['report'];

    // 2) Kind-specific blackboard deliverable.
    final need = switch (step.kind) {
      FlowStepKind.orchestrator => 'plan',
      FlowStepKind.decision => 'verdict',
      FlowStepKind.rfcCreate => 'rfc_id',
      FlowStepKind.rfcConsolidate => 'plan',
      _ => null,
    };
    if (need != null &&
        !await _requireBlackboard(run, need, updatedBy: reported.id)) {
      return t[need];
    }
    // Verdict-only routing: when this step's ONLY way forward is a verdict
    // connection, the agent MUST have written one — whatever the kind.
    if (verdictRequired &&
        need != 'verdict' &&
        !await _requireBlackboard(run, 'verdict', updatedBy: reported.id)) {
      return t['verdict'];
    }
    return null;
  }

  /// The highest iteration already recorded for (run, step) — 0 when none. A
  /// loop-back RE-VISITS a step; its new iterations continue from here (the
  /// (run, step, iteration) triple is unique in the database).
  Future<int> _nextIterationBase(FlowRunEntity run, IdVO stepId) async {
    final bundle = await _repo.getRun(run.id);
    var maxIteration = 0;
    if (bundle.isSuccess()) {
      for (final s in bundle.getOrThrow().steps) {
        if (s.stepId.value == stepId.value && s.iteration > maxIteration) {
          maxIteration = s.iteration;
        }
      }
    }
    return maxIteration;
  }

  /// Latest native CLI conversation for this logical node. Keeping this in a
  /// real column (rather than transient worker memory or verifier JSON) makes
  /// continuity survive pause/resume, worker crashes and graph loop-backs.
  Future<String?> _latestAgentSessionId(FlowRunEntity run, IdVO stepId) async {
    final bundle = await _repo.getRun(run.id);
    if (bundle.isError()) return null;
    FlowRunStepEntity? latest;
    for (final candidate in bundle.getOrThrow().steps) {
      if (candidate.stepId.value != stepId.value ||
          (candidate.agentSessionId ?? '').trim().isEmpty) {
        continue;
      }
      if (latest == null || candidate.iteration > latest.iteration) {
        latest = candidate;
      }
    }
    return latest?.agentSessionId?.trim();
  }

  Future<int> _latestAgentSessionTotalTokens(
    FlowRunEntity run,
    IdVO stepId,
    String agentSessionId,
  ) async {
    final bundle = await _repo.getRun(run.id);
    if (bundle.isError()) return 0;
    var latestIteration = -1;
    var latestTotal = 0;
    for (final item in bundle.getOrThrow().steps) {
      if (item.stepId != stepId ||
          item.agentSessionId != agentSessionId ||
          item.iteration <= latestIteration) {
        continue;
      }
      var total = 0;
      try {
        final verifier = jsonDecode(item.verifier ?? '{}');
        if (verifier is Map && verifier['agentSessionTotalTokens'] is num) {
          total = (verifier['agentSessionTotalTokens'] as num).toInt();
        }
      } catch (_) {
        // Runs created before v2.2.9 stored Codex's cumulative value directly.
      }
      if (total <= 0) total = item.tokensUsed;
      // The current iteration is already present while it is running, but has
      // no usage yet. Do not let that zero-valued row hide the preceding
      // cumulative total of the resumed Codex session.
      if (total <= 0) continue;
      latestIteration = item.iteration;
      latestTotal = total;
    }
    return latestTotal;
  }

  /// Reads (and CONSUMES) a user-forced skip request for [stepKey] from the
  /// blackboard key `_skip` — written by the Studio as
  /// `{"step": "<key>", "verdict": "<route>"|null}`. The optional verdict picks
  /// which connection to follow when the step has verdict-only routes.
  Future<({bool requested, String? verdict})> _takeSkip(
    FlowRunEntity run,
    String stepKey,
  ) async {
    final bundle = await _repo.getRun(run.id);
    if (bundle.isError()) return (requested: false, verdict: null);
    for (final c in bundle.getOrThrow().context) {
      if (c.key != '_skip') continue;
      try {
        final j = jsonDecode(c.value);
        if (j is Map && '${j['step']}' == stepKey) {
          await _repo.putContext(
            FlowRunContextEntity(runId: run.id, key: '_skip', value: '""'),
          );
          final v = '${j['verdict'] ?? ''}'.trim();
          return (requested: true, verdict: v.isEmpty ? null : v);
        }
      } catch (_) {
        /* not a skip payload */
      }
    }
    return (requested: false, verdict: null);
  }

  /// Records a user-forced skip: the step is marked `skipped` (never a silent
  /// hole in the audit trail) and the flow follows [verdict] or success edges.
  Future<_StepResult> _skipStep(
    FlowRunEntity run,
    FlowStepEntity step,
    String? verdict,
  ) async {
    final startResult = await _repo.startRunStep(
      FlowRunStepEntity(
        id: const IdVO.empty(),
        runId: run.id,
        stepId: step.id,
        iteration: await _nextIterationBase(run, step.id) + 1,
        status: FlowRunStepStatus.running,
        claimToken: _claimToken(run),
      ),
    );
    if (startResult.isSuccess()) {
      await _repo.updateRunStep(
        startResult.getOrThrow().copyWith(
          status: FlowRunStepStatus.skipped,
          verifier: jsonEncode({
            'skipped': true,
            'forced': true,
            if (verdict != null) 'verdict': verdict,
          }),
        ),
      );
    }
    await _event(run.id, 'state', {
      'step': step.stepKey,
      'skipped': true,
      'forced': true,
    });
    return _StepResult(_Outcome.success, verdict: verdict);
  }

  /// Does this launch failure look like an exhausted plan/quota/rate limit?
  /// Conservative pattern match over the CLI's stderr/stdout tail.
  static bool _isQuotaFailure(String s) => RegExp(
    r'rate.?limit|usage.?limit|quota|credit|too many requests|429'
    r'|insufficient|limit (reached|exceeded)|out of (credits|tokens)'
    r'|overloaded',
    caseSensitive: false,
  ).hasMatch(s);

  /// Matches the terminal messages emitted when an agent host cancels a nested
  /// MCP invocation before it reaches Oracle.
  static bool _isMcpConnectorCancellation(String s) => RegExp(
    r'(mcp|oracle).{0,80}(cancel(?:led|ado|ada)|conector.{0,40}cancel)'
    r'|cancel(?:led|ado|ada).{0,80}(mcp|oracle|conector)'
    r'|user cancelled mcp tool call',
    caseSensitive: false,
    dotAll: true,
  ).hasMatch(s);

  /// True when the run's blackboard has a non-empty value for [key].
  Future<bool> _requireBlackboard(
    FlowRunEntity run,
    String key, {
    IdVO? updatedBy,
  }) async {
    final bundle = await _repo.getRun(run.id);
    return bundle.isSuccess() &&
        bundle.getOrThrow().context.any((c) {
          if (c.key != key) return false;
          if (updatedBy != null && c.updatedBy?.value != updatedBy.value) {
            return false;
          }
          final v = c.value.trim();
          return v.isNotEmpty && v != '{}' && v != '""' && v != 'null';
        });
  }

  static const _reqPt = {
    'report':
        'PROTOCOLO NÃO CUMPRIDO: você não chamou oracle_flow_step_report. Verifique se as '
        'tools MCP do oracle-ai estão acessíveis neste repositório (.mcp.json) e SEMPRE '
        'finalize com oracle_flow_step_report(runStepId, summary, status).',
    'connectorCancelled':
        'O host do agente cancelou uma chamada MCP do Oracle antes de ela chegar ao servidor. '
        'A execução foi pausada sem repetir a mesma tentativa; revise a integração do agente '
        'e retome a tarefa.',
    'plan':
        'REQUISITO DA ETAPA NÃO CUMPRIDO: o plano não foi gravado no blackboard. Chame '
        'oracle_flow_context_put com key "plan" contendo o plano de implementação e o '
        'brief objetivo das próximas etapas. NÃO implemente código nesta etapa.',
    'rfc_id':
        'REQUISITO DA ETAPA NÃO CUMPRIDO: o id da RFC não foi gravado no blackboard. Crie a '
        'RFC com oracle_rfc_open e grave o id com oracle_flow_context_put key "rfc_id" '
        '(e registre o artifact kind "rfc").',
    'rfc_id_pre':
        'PRÉ-REQUISITO AUSENTE: não há "rfc_id" no blackboard deste run — a etapa de '
        'Criação de RFC precisa executar ANTES desta (e gravar o id). Ajuste as conexões '
        'do processo ou aprove após corrigir.',
    'verdict':
        'REQUISITO DA ETAPA NÃO CUMPRIDO: o veredito não foi gravado no blackboard. Um nó '
        'de decisão DEVE chamar oracle_flow_context_put com key "verdict" e EXATAMENTE '
        'um dos valores listados na seção "Veredito" do prompt — o runner roteia o '
        'fluxo por esse valor.',
    'subflow_key':
        'ETAPA SUB-PROCESSO SEM ALVO: informe qual processo executar no campo '
        '"Processo" da etapa (config flowKey).',
    'subflow_missing': 'Sub-processo não encontrado',
    'subflow_failed': 'O sub-processo não concluiu',
    'subflow_depth':
        'Limite de aninhamento de sub-processos atingido (3 níveis) — verifique se um '
        'processo não está chamando a si mesmo.',
    'protocolOnly':
        'NÃO REFAÇA O TRABALHO. A tentativa anterior COMPLETOU a análise/implementação — o '
        'que faltou foi SOMENTE o protocolo MCP. Não re-analise, não re-implemente, não '
        'repita nada: apenas execute as chamadas que faltaram (oracle_flow_step_context '
        'se precisar do runStepId, depois as chamadas abaixo) e finalize em poucos '
        'minutos.',
    'protocolOnlyPrior':
        'RESULTADO JÁ PRODUZIDO na tentativa anterior — use como base do seu report '
        '(resuma-o em oracle_flow_step_report; NÃO refaça a análise):',
  };

  static const _reqEn = {
    'report':
        'PROTOCOL NOT FULFILLED: you did not call oracle_flow_step_report. Check that the '
        'oracle-ai MCP tools are reachable in this repository (.mcp.json) and ALWAYS '
        'finish with oracle_flow_step_report(runStepId, summary, status).',
    'connectorCancelled':
        'The agent host cancelled an Oracle MCP call before it reached the server. The run '
        'was parked without repeating the same attempt; review the agent integration and '
        'resume the task.',
    'plan':
        'STEP REQUIREMENT NOT MET: the plan was not written to the blackboard. Call '
        'oracle_flow_context_put with key "plan" containing the implementation plan and '
        'an objective brief for the next steps. Do NOT implement code in this step.',
    'rfc_id':
        'STEP REQUIREMENT NOT MET: the RFC id was not written to the blackboard. Create the '
        'RFC with oracle_rfc_open and write the id with oracle_flow_context_put key '
        '"rfc_id" (and register the artifact kind "rfc").',
    'rfc_id_pre':
        'PRECONDITION MISSING: there is no "rfc_id" on this run\'s blackboard — the RFC '
        'creation step must execute BEFORE this one (and write the id). Fix the process '
        'connections or approve after correcting.',
    'verdict':
        'STEP REQUIREMENT NOT MET: the verdict was not written to the blackboard. A '
        'decision node MUST call oracle_flow_context_put with key "verdict" and EXACTLY '
        'one of the values listed in the prompt\'s "Verdict" section — the runner routes '
        'the flow on that value.',
    'subflow_key':
        'SUB-PROCESS STEP WITHOUT A TARGET: set which process to execute in the step\'s '
        '"Process" field (config flowKey).',
    'subflow_missing': 'Sub-process not found',
    'subflow_failed': 'The sub-process did not complete',
    'subflow_depth':
        'Sub-process nesting limit reached (3 levels) — check whether a process is '
        'calling itself.',
    'protocolOnly':
        'DO NOT REDO THE WORK. The previous attempt COMPLETED the analysis/implementation — '
        'only the MCP protocol was missing. Do not re-analyze, do not re-implement, do '
        'not repeat anything: just make the missing calls (oracle_flow_step_context if '
        'you need the runStepId, then the calls below) and finish within minutes.',
    'protocolOnlyPrior':
        'RESULT ALREADY PRODUCED by the previous attempt — use it as the basis of your '
        'report (summarize it into oracle_flow_step_report; do NOT redo the analysis):',
  };

  /// The DETERMINISTIC RFC round gate (no LLM). Reads `rfc_id` from the run's
  /// blackboard, queries the RFC engine and decides the route:
  /// - `limite`    — visits EXCEEDED `maxRounds` (hard budget, beats all), or
  ///   reached it without a clean/dry state (config, default 3);
  /// - `concluir`  — no verified criticals + no open majors, OR no NEW findings
  ///   since the last visit (dry) — but only AFTER something was reviewed
  ///   (a fresh RFC is vacuously clean and must not conclude on visit 1);
  /// - `continuar` — otherwise: opens the next engine round and loops back.
  /// The decision (and every number behind it) lands in the step's verifier
  /// payload, so the monitor shows exactly WHY it routed where it did.
  Future<_StepResult> _runRfcGate(
    FlowRunEntity run,
    FlowStepEntity step,
  ) async {
    final startResult = await _repo.startRunStep(
      FlowRunStepEntity(
        id: const IdVO.empty(),
        runId: run.id,
        stepId: step.id,
        iteration: await _nextIterationBase(run, step.id) + 1,
        status: FlowRunStepStatus.running,
        claimToken: _claimToken(run),
      ),
    );
    if (startResult.isError()) return const _StepResult(_Outcome.failure);
    var runStep = startResult.getOrThrow();

    Future<void> finish(bool passed, Map<String, Object?> payload) async {
      runStep = runStep.copyWith(
        status: passed ? FlowRunStepStatus.passed : FlowRunStepStatus.failed,
        verifier: jsonEncode(payload),
      );
      await _repo.updateRunStep(runStep);
    }

    // The RFC under review comes from the blackboard (rfc_create writes it).
    final bundle = await _repo.getRun(run.id);
    String? rfcId;
    Map<String, dynamic> gateState = const {};
    if (bundle.isSuccess()) {
      for (final c in bundle.getOrThrow().context) {
        if (c.key == 'rfc_id') {
          try {
            final decoded = jsonDecode(c.value);
            rfcId = decoded is String ? decoded : '${decoded ?? ''}';
          } catch (_) {
            rfcId = c.value;
          }
        }
        if (c.key == '_rfc_gate') {
          try {
            final decoded = jsonDecode(c.value);
            if (decoded is Map<String, dynamic>) gateState = decoded;
          } catch (_) {
            /* fresh */
          }
        }
      }
    }
    if (rfcId == null || rfcId.trim().isEmpty) {
      await finish(false, {'error': 'rfc_id not found in blackboard'});
      return const _StepResult(_Outcome.failure);
    }

    final statusResult = await injector.get<RfcStatusUsecase>()(IdVO(rfcId));
    if (statusResult.isError()) {
      await finish(false, {
        'error': statusResult.exceptionOrNull()!.errorMessage,
      });
      return const _StepResult(_Outcome.failure);
    }
    final status = statusResult.getOrThrow();

    final maxRounds = _configInt(step.config, 'maxRounds') ?? 3;
    final visits = (gateState['visits'] as num? ?? 0).toInt() + 1;
    final lastTotal = (gateState['lastTotal'] as num? ?? -1).toInt();

    final clean = status.blockingCriticals == 0 && status.openMajors == 0;
    // A fresh RFC is vacuously "clean" — the gate may only CONCLUDE after at
    // least one review happened (comments exist, or this is a revisit). This
    // keeps gate-before-review topologies from concluding before reviewing.
    final reviewedYet = status.totalComments > 0 || visits > 1;
    final String verdict;
    if (visits > maxRounds) {
      // HARD budget: past the cap nothing loops again — not even "clean"
      // (an eternally-revisited gate would otherwise never emit `limite`).
      verdict = 'limite';
    } else if (clean && reviewedYet) {
      verdict = 'concluir';
    } else if (visits >= maxRounds) {
      verdict = 'limite';
    } else {
      verdict = 'continuar';
      // Bracket the engine rounds (best-effort): close the current, open the next.
      try {
        final rfc = await injector.get<GetRfcUsecase>()(IdVO(rfcId));
        if (rfc.isSuccess() && rfc.getOrThrow().rfc.roundCount > 0) {
          await injector.get<CloseRoundUsecase>()(
            rfcId: IdVO(rfcId),
            roundNo: rfc.getOrThrow().rfc.roundCount,
          );
        }
        await injector.get<StartRoundUsecase>()(
          RfcRoundEntity(
            id: const IdVO.empty(),
            rfcId: IdVO(rfcId),
            roundNo: 0, // auto-next
          ),
        );
      } catch (_) {
        /* rounds bookkeeping is advisory */
      }
    }

    await _repo.putContext(
      FlowRunContextEntity(
        runId: run.id,
        key: '_rfc_gate',
        value: jsonEncode({
          'visits': visits,
          'lastTotal': status.totalComments,
        }),
        updatedBy: runStep.id,
      ),
    );
    await finish(true, {
      'decision': verdict,
      'round': visits,
      'maxRounds': maxRounds,
      'blockingCriticals': status.blockingCriticals,
      'openMajors': status.openMajors,
      'totalComments': status.totalComments,
      'newFindings': lastTotal < 0
          ? status.totalComments
          : status.totalComments - lastTotal,
    });
    await _event(run.id, 'decision', {
      'step': step.stepKey,
      'verdict': verdict,
      'round': visits,
    });
    return _StepResult(_Outcome.success, verdict: verdict);
  }

  /// Validates the useful `outputs` portion of a step report against the
  /// configured JSON Schema subset (type, required, properties, items, enum).
  /// Invalid schema is a configuration failure, never a silent pass.
  static String? _validateOutputSchema(String? rawSchema, String? rawReport) {
    if (rawSchema == null ||
        rawSchema.trim().isEmpty ||
        rawSchema.trim() == '{}') {
      return null;
    }
    try {
      final schema = jsonDecode(rawSchema);
      if (schema is! Map) return 'outputSchema must be a JSON object';
      final report = jsonDecode(rawReport ?? '{}');
      final value = report is Map && report.containsKey('outputs')
          ? report['outputs']
          : report;
      return _schemaError(schema, value, r'$outputs');
    } catch (error) {
      return 'Invalid output schema or report JSON: $error';
    }
  }

  static String? _schemaError(
    Map<Object?, Object?> schema,
    Object? value,
    String path,
  ) {
    final expected = schema['type']?.toString();
    final validType = switch (expected) {
      null => true,
      'object' => value is Map,
      'array' => value is List,
      'string' => value is String,
      'integer' => value is int,
      'number' => value is num,
      'boolean' => value is bool,
      'null' => value == null,
      _ => false,
    };
    if (!validType) return '$path must be $expected';
    final allowed = schema['enum'];
    if (allowed is List && !allowed.contains(value)) {
      return '$path must be one of ${allowed.join(', ')}';
    }
    if (value is Map) {
      final required = schema['required'];
      if (required is List) {
        for (final key in required.map((e) => e.toString())) {
          if (!value.containsKey(key)) return '$path.$key is required';
        }
      }
      final properties = schema['properties'];
      if (properties is Map) {
        for (final entry in properties.entries) {
          if (!value.containsKey(entry.key) || entry.value is! Map) continue;
          final error = _schemaError(
            (entry.value as Map).cast<Object?, Object?>(),
            value[entry.key],
            '$path.${entry.key}',
          );
          if (error != null) return error;
        }
      }
    }
    if (value is List && schema['items'] is Map) {
      for (var index = 0; index < value.length; index++) {
        final error = _schemaError(
          (schema['items'] as Map).cast<Object?, Object?>(),
          value[index],
          '$path[$index]',
        );
        if (error != null) return error;
      }
    }
    return null;
  }

  static String _clip(String s, [int max = 600]) =>
      s.length <= max ? s : '${s.substring(0, max)}…';

  /// An int value out of the step's config json.
  static int? _configInt(String configJson, String key) {
    try {
      final j = jsonDecode(configJson);
      if (j is Map && j[key] is num) return (j[key] as num).toInt();
    } catch (_) {
      /* none */
    }
    return null;
  }

  /// A string value out of the step's config json.
  static String? _configString(String configJson, String key) {
    try {
      final j = jsonDecode(configJson);
      if (j is Map && j[key] is String) {
        final v = (j[key] as String).trim();
        return v.isEmpty ? null : v;
      }
    } catch (_) {
      /* none */
    }
    return null;
  }

  /// Attribution handed to the agent process — and inherited by the Oracle MCP
  /// server the agent spawns — so every Oracle call lands on the RUN's project,
  /// even when the cwd is a worktree or temp dir.
  Map<String, String> _agentEnv(FlowRunEntity run, FlowRunStepEntity runStep) =>
      {
        if (run.projectId != null) 'ORACLE_PROJECT_ID': run.projectId!.value,
        'ORACLE_RUN_ID': run.id.value,
        'ORACLE_RUN_STEP_ID': runStep.id.value,
        if (runStep.sessionId != null)
          'ORACLE_SESSION_ID': runStep.sessionId!.value,
        if (runStep.claimToken != null)
          'ORACLE_RUN_STEP_TOKEN': runStep.claimToken!,
        'ORACLE_LANG': language,
      };

  static String _claimToken(FlowRunEntity run) =>
      '${run.id.value}:${run.leaseEpoch}';

  /// The exact edges selected for this outcome. Keeping the edge identity (not
  /// only the target key) lets the monitor distinguish parallel success and
  /// verdict connections that point to the same node.
  List<FlowEdgeEntity> _matchingEdges(
    FlowGraph graph,
    FlowStepEntity step,
    bool passed,
    String? verdict,
  ) {
    final out = graph.edges
        .where((e) => e.fromStep.value == step.id.value)
        .toList();
    final selected = <FlowEdgeEntity>[];
    void addAll(bool Function(FlowEdgeEntity) test) {
      for (final e in out) {
        if (test(e) && !selected.any((item) => item.id == e.id)) {
          selected.add(e);
        }
      }
    }

    if (passed) {
      if (verdict != null) {
        final want = verdict.trim().toLowerCase();
        addAll(
          (e) =>
              e.condition == 'verdict' &&
              (e.verdictValue ?? '').trim().toLowerCase() == want,
        );
      }
      if (selected.isEmpty) addAll((e) => e.condition == 'success');
    } else {
      addAll((e) => e.condition == 'failure');
    }
    if (selected.isEmpty) addAll((e) => e.condition == 'always');
    return selected;
  }

  Future<String?> _readVerdict(IdVO runId, {IdVO? updatedBy}) async {
    final bundle = await _repo.getRun(runId);
    if (bundle.isError()) return null;
    for (final c in bundle.getOrThrow().context) {
      if (c.key == 'verdict') {
        if (updatedBy != null && c.updatedBy?.value != updatedBy.value) {
          continue;
        }
        String raw;
        try {
          final decoded = jsonDecode(c.value);
          raw = decoded is String ? decoded : decoded.toString();
        } catch (_) {
          raw = c.value;
        }
        final v = raw.trim();
        // A consumed ('""') or empty/null verdict is NO verdict.
        return v.isEmpty || v == 'null' ? null : v;
      }
    }
    return null;
  }

  /// True when the run's accumulated tokens reached `budgets.maxTotalTokens`
  /// (0/absent = no cap). The token count is best-effort (see [StepLauncher]).
  bool _overBudget(String budgetsJson, int tokensUsed) {
    try {
      final b = jsonDecode(budgetsJson);
      if (b is Map) {
        final max = b['maxTotalTokens'];
        if (max is num && max > 0) return tokensUsed >= max.toInt();
      }
    } catch (_) {
      /* no budget */
    }
    return false;
  }

  bool _overWallBudget(FlowRunEntity run) {
    final started = run.startedAt;
    if (started == null) return false;
    try {
      final budgets = jsonDecode(run.budgets);
      if (budgets is Map && budgets['maxWallMinutes'] is num) {
        final max = (budgets['maxWallMinutes'] as num).toInt();
        return max > 0 && DateTime.now().difference(started).inMinutes >= max;
      }
    } catch (_) {
      // Invalid budgets are rejected by preflight; legacy runs remain uncapped.
    }
    return false;
  }

  Future<void> _finalize(
    FlowRunEntity run,
    TaskEntity? task,
    FlowRunStatus status, {
    required String workerId,
  }) async {
    final updated = await _repo.updateRunStatus(
      run.id,
      status,
      expectedWorkerId: workerId,
      expectedLeaseEpoch: run.leaseEpoch,
      expectedStatuses: const {FlowRunStatus.running},
    );
    if (updated.isError()) throw const _LeaseLost();
    await _event(run.id, 'state', {'final': status.code});
    if (task != null) {
      await _repo.updateTask(
        task.id,
        status: status == FlowRunStatus.completed
            ? TaskStatus.done
            : TaskStatus.blocked,
      );
    }
    stderr.writeln(
      '[oracle] flow-worker run ${run.id.value} -> ${status.code}',
    );
  }

  Future<void> _event(
    IdVO runId,
    String kind,
    Map<String, dynamic> payload,
  ) async {
    await _safeEvent(runId, kind, payload);
  }

  /// Telemetry must never change the business outcome of a run. A temporary
  /// event-table failure is observable in server logs, but cannot turn an
  /// already completed process into a failed process.
  Future<void> _safeEvent(
    IdVO runId,
    String kind,
    Map<String, dynamic> payload,
  ) async {
    try {
      await _repo.addEvent(
        FlowRunEventEntity(
          id: const IdVO.empty(),
          runId: runId,
          kind: kind,
          payload: jsonEncode(payload),
        ),
      );
    } catch (error) {
      stderr.writeln('[oracle] event $kind for ${runId.value} failed: $error');
    }
  }

  /// The repo root a run works in. Running in the server's own current
  /// directory when project configuration is missing can modify the wrong
  /// repository, so project-bound runs fail closed.
  Future<String> _resolveRepoRoot(FlowRunEntity run) async {
    final projectId = run.projectId;
    if (projectId != null && projectId.isNotEmpty) {
      try {
        final result = await injector.get<GetProjectByIdUsecase>()(projectId);
        if (result.isSuccess()) {
          final path = result.getOrThrow().repoPath;
          if (path != null &&
              path.trim().isNotEmpty &&
              Directory(path).existsSync()) {
            return path;
          }
        }
      } catch (_) {
        // Report the single safe error below.
      }
      throw StateError(
        'Project ${projectId.value} has no valid repository path',
      );
    }
    // Legacy runs without a project intentionally keep the old local behavior.
    return Directory.current.path;
  }

  String _slug(TaskEntity? task, FlowEntity flow) {
    final base = task?.title.value.isNotEmpty == true
        ? task!.title.value
        : flow.key;
    final slug = base
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final trimmed = slug.length > 40 ? slug.substring(0, 40) : slug;
    return trimmed.isEmpty ? 'run' : trimmed;
  }
}
