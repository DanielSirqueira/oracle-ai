import 'dart:async';

import 'package:flutter/material.dart';
import 'package:oracle_memory/oracle_memory.dart';

import '../../core/brand.dart';
import '../../core/l10n.dart';
import 'flow_labels.dart';

/// In-app, localized, VISUAL documentation of Loop Engineering: concept cards,
/// the 4-step cycle, an ANIMATED example run, the under-the-hood pipeline, the
/// REAL launch commands per agent, how each step learns what the previous one
/// did, the node-type gallery with when-to-use, field reference, connection
/// semantics, prerequisites, tasks and best practices. Responsive (wraps on
/// narrow widths) — no markdown wall of text.
class FlowGuidePage extends StatelessWidget {
  const FlowGuidePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OracleBrand.gray950,
      appBar: AppBar(
        backgroundColor: OracleBrand.gray900,
        title: Text(l10n.t('flows.guideTitle')),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 48),
            children: [
              // ── hero ──
              Text(
                l10n.t('g.heroTitle'),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 6),
              Text(
                l10n.t('g.heroSub'),
                style: const TextStyle(
                  fontSize: 13.5,
                  color: OracleBrand.gray400,
                ),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _wrapCard(
                    300,
                    _ConceptCard(
                      icon: Icons.account_tree_outlined,
                      color: OracleBrand.violet,
                      title: l10n.t('g.cProcess'),
                      body: l10n.t('g.cProcessBody'),
                    ),
                  ),
                  _wrapCard(
                    300,
                    _ConceptCard(
                      icon: Icons.checklist_outlined,
                      color: OracleBrand.blue,
                      title: l10n.t('g.cTask'),
                      body: l10n.t('g.cTaskBody'),
                    ),
                  ),
                  _wrapCard(
                    300,
                    _ConceptCard(
                      icon: Icons.play_circle_outline,
                      color: OracleBrand.success,
                      title: l10n.t('g.cRun'),
                      body: l10n.t('g.cRunBody'),
                    ),
                  ),
                ],
              ),

              _sectionTitle(
                context,
                Icons.route_outlined,
                l10n.t('g.cycleTitle'),
              ),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (var i = 1; i <= 4; i++)
                    _wrapCard(
                      222,
                      _NumStep(
                        n: i,
                        title: l10n.t('g.cycle$i'),
                        body: l10n.t('g.cycle${i}Body'),
                      ),
                    ),
                ],
              ),

              // ── ANIMATED example run ──
              _sectionTitle(
                context,
                Icons.schema_outlined,
                l10n.t('g.exampleTitle'),
              ),
              _card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _AnimatedFlowDemo(),
                    const SizedBox(height: 6),
                    Text(
                      l10n.t('g.demoCaption'),
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: OracleBrand.gray500,
                      ),
                    ),
                    const Divider(height: 22),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.u_turn_left,
                          size: 15,
                          color: OracleBrand.warning,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            l10n.t('g.exampleNote'),
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: OracleBrand.gray400,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // ── under the hood ──
              _sectionTitle(
                context,
                Icons.settings_suggest_outlined,
                l10n.t('g.hoodTitle'),
              ),
              _card(
                child: Column(
                  children: [
                    for (var i = 1; i <= 8; i++)
                      _HoodStep(
                        n: i,
                        last: i == 8,
                        icon: _hoodIcons[i - 1],
                        title: l10n.t('g.hood$i'),
                        body: l10n.t('g.hood${i}Body'),
                        extra: i == 4
                            ? Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: [
                                    for (final k in const [
                                      'g.chipTask',
                                      'g.chipRules',
                                      'g.chipSkills',
                                      'g.chipBlackboard',
                                      'g.chipReports',
                                      'g.chipCriteria',
                                    ])
                                      _chip(l10n.t(k)),
                                  ],
                                ),
                              )
                            : null,
                      ),
                  ],
                ),
              ),

              // ── the REAL commands under everything ──
              _sectionTitle(
                context,
                Icons.terminal_outlined,
                l10n.t('g.cmdTitle'),
              ),
              _card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.t('g.cmdBody'),
                      style: const TextStyle(fontSize: 13, height: 1.5),
                    ),
                    const SizedBox(height: 12),
                    const _CmdCard(
                      agent: 'Claude Code',
                      command:
                          'claude -p "<prompt>" --output-format json --permission-mode acceptEdits --allowedTools "Bash,mcp__oracle-ai"',
                    ),
                    const _CmdCard(
                      agent: 'Codex',
                      command:
                          'codex exec "<prompt>" --sandbox workspace-write -C <worktree>',
                    ),
                    const _CmdCard(
                      agent: 'Gemini CLI',
                      command: 'gemini -p "<prompt>" --approval-mode auto_edit',
                    ),
                    const _CmdCard(
                      agent: 'Cursor',
                      command: 'cursor-agent -p "<prompt>" --force',
                    ),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.info_outline,
                          size: 15,
                          color: OracleBrand.gray500,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            l10n.t('g.cmdNote'),
                            style: const TextStyle(
                              fontSize: 12,
                              color: OracleBrand.gray400,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // ── how the next step knows what happened ──
              _sectionTitle(context, Icons.sync_alt, l10n.t('g.ctxTitle')),
              _card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.t('g.ctxBody'),
                      style: const TextStyle(fontSize: 13, height: 1.5),
                    ),
                    const SizedBox(height: 14),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          _ctxBox(
                            l10n.t('g.ctxStepN'),
                            OracleBrand.violet,
                            Icons.smart_toy_outlined,
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            child: Icon(
                              Icons.arrow_forward,
                              size: 16,
                              color: OracleBrand.gray500,
                            ),
                          ),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                l10n.t('g.ctxProduces'),
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  color: OracleBrand.gray500,
                                ),
                              ),
                              const SizedBox(height: 6),
                              _chip(l10n.t('g.ctxChipReport')),
                              const SizedBox(height: 4),
                              _chip(l10n.t('g.ctxChipBlackboard')),
                              const SizedBox(height: 4),
                              _chip(l10n.t('g.ctxChipArtifacts')),
                              const SizedBox(height: 4),
                              _chip(l10n.t('g.ctxChipCommit')),
                            ],
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            child: Icon(
                              Icons.arrow_forward,
                              size: 16,
                              color: OracleBrand.gray500,
                            ),
                          ),
                          _ctxBox(
                            l10n.t('g.ctxStepN1'),
                            OracleBrand.blue,
                            Icons.smart_toy_outlined,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _bullet(Icons.chat_outlined, l10n.t('g.ctx1')),
                    _bullet(
                      Icons.dashboard_customize_outlined,
                      l10n.t('g.ctx2'),
                    ),
                    _bullet(Icons.build_circle_outlined, l10n.t('g.ctx3')),
                    _bullet(Icons.block_outlined, l10n.t('g.ctx4')),
                  ],
                ),
              ),

              // ── node types (with when-to-use) ──
              _sectionTitle(
                context,
                Icons.category_outlined,
                l10n.t('g.kindsTitle'),
              ),
              for (final k in FlowStepKind.values)
                _card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                          color: kindColor(k).withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Icon(kindIcon(k), size: 19, color: kindColor(k)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              kindLabel(k),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              kindDescription(k),
                              style: const TextStyle(
                                fontSize: 12.5,
                                color: OracleBrand.gray400,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.lightbulb_outline,
                                  size: 13,
                                  color: kindColor(k),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    l10n.t('g.kindUse.${k.code}'),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: kindColor(k),
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (k == FlowStepKind.orchestrator) ...[
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.flag,
                                    size: 14,
                                    color: OracleBrand.success,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      l10n.t('g.kindsNote'),
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: OracleBrand.success,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            if (k == FlowStepKind.decision) ...[
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.call_split,
                                    size: 14,
                                    color: OracleBrand.warning,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      l10n.t('g.decisionNote'),
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: OracleBrand.warning,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

              // ── step fields ──
              _sectionTitle(context, Icons.tune, l10n.t('g.fieldsTitle')),
              _card(
                child: Column(
                  children: [
                    _FieldRef(
                      icon: Icons.smart_toy_outlined,
                      name:
                          '${l10n.t('flows.fAgent')} / ${l10n.t('flows.fModel')}',
                      body: l10n.t('g.fAgent'),
                    ),
                    _FieldRef(
                      icon: Icons.badge_outlined,
                      name: l10n.t('flows.fRole'),
                      body: l10n.t('flows.fRoleDesc'),
                    ),
                    _FieldRef(
                      icon: Icons.chat_outlined,
                      name: l10n.t('flows.fPrompt'),
                      body: l10n.t('g.fPrompt'),
                    ),
                    _FieldRef(
                      icon: Icons.school_outlined,
                      name: l10n.t('flows.fSkills'),
                      body: l10n.t('flows.fSkillsDesc'),
                    ),
                    _FieldRef(
                      icon: Icons.rule_outlined,
                      name: l10n.t('flows.fExit'),
                      body: l10n.t('g.fExit'),
                    ),
                    _FieldRef(
                      icon: Icons.loop,
                      name: l10n.t('flows.fMaxIter'),
                      body: l10n.t('g.fMaxIter'),
                    ),
                    _FieldRef(
                      icon: Icons.timer_outlined,
                      name: l10n.t('flows.fTimeout'),
                      body: l10n.t('flows.fTimeoutDesc'),
                    ),
                    _FieldRef(
                      icon: Icons.error_outline,
                      name: l10n.t('flows.fOnFail'),
                      body: l10n.t('g.fOnFail'),
                      last: true,
                    ),
                  ],
                ),
              ),

              // ── connections ──
              _sectionTitle(context, Icons.alt_route, l10n.t('g.connTitle')),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _wrapCard(
                    222,
                    _CondCard(
                      code: 'success',
                      color: OracleBrand.gray500,
                      body: l10n.t('g.connSuccess'),
                    ),
                  ),
                  _wrapCard(
                    222,
                    _CondCard(
                      code: 'failure',
                      color: OracleBrand.error,
                      body: l10n.t('g.connFailure'),
                    ),
                  ),
                  _wrapCard(
                    222,
                    _CondCard(
                      code: 'verdict',
                      color: OracleBrand.warning,
                      body: l10n.t('g.connVerdict'),
                    ),
                  ),
                  _wrapCard(
                    222,
                    _CondCard(
                      code: 'always',
                      color: OracleBrand.blue,
                      body: l10n.t('g.connAlways'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _bullet(Icons.call_split, l10n.t('g.connFanout')),
                    _bullet(Icons.call_merge, l10n.t('g.connJoin')),
                    _bullet(Icons.u_turn_left, l10n.t('g.connLoop')),
                  ],
                ),
              ),

              // ── prerequisites ──
              _sectionTitle(context, Icons.checklist_rtl, l10n.t('g.preTitle')),
              _card(
                child: Column(
                  children: [
                    _Check(text: l10n.t('g.pre1')),
                    _Check(text: l10n.t('g.pre2')),
                    _Check(text: l10n.t('g.pre3'), last: true),
                  ],
                ),
              ),

              // ── tasks ──
              _sectionTitle(
                context,
                Icons.checklist_outlined,
                l10n.t('g.tasksTitle'),
              ),
              _card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.t('g.tasksBody'),
                      style: const TextStyle(fontSize: 13, height: 1.5),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final s in TaskStatus.values)
                          StatusBadgeLike(
                            label: taskStatusLabel(s),
                            color: taskStatusColor(s),
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              // ── monitoring ──
              _sectionTitle(
                context,
                Icons.monitor_heart_outlined,
                l10n.t('g.monTitle'),
              ),
              _card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _bullet(Icons.chat_outlined, l10n.t('g.mon1')),
                    _bullet(
                      Icons.assignment_turned_in_outlined,
                      l10n.t('g.mon2'),
                    ),
                    _bullet(Icons.rule_outlined, l10n.t('g.mon3')),
                    _bullet(Icons.terminal_outlined, l10n.t('g.mon5')),
                    _bullet(Icons.pan_tool_outlined, l10n.t('g.mon4')),
                  ],
                ),
              ),

              // ── best practices ──
              _sectionTitle(
                context,
                Icons.workspace_premium_outlined,
                l10n.t('g.bestTitle'),
              ),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _wrapCard(
                    452,
                    _card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.thumb_up_outlined,
                                size: 16,
                                color: OracleBrand.success,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                l10n.t('g.doTitle'),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: OracleBrand.success,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          for (var i = 1; i <= 4; i++)
                            _bullet(
                              Icons.check,
                              l10n.t('g.do$i'),
                              color: OracleBrand.success,
                            ),
                        ],
                      ),
                    ),
                  ),
                  _wrapCard(
                    452,
                    _card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.thumb_down_outlined,
                                size: 16,
                                color: OracleBrand.error,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                l10n.t('g.dontTitle'),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: OracleBrand.error,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          for (var i = 1; i <= 4; i++)
                            _bullet(
                              Icons.close,
                              l10n.t('g.dont$i'),
                              color: OracleBrand.error,
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static const _hoodIcons = [
    Icons.queue_outlined,
    Icons.front_hand_outlined,
    Icons.merge_type,
    Icons.chat_outlined,
    Icons.rocket_launch_outlined,
    Icons.rule_outlined,
    Icons.alt_route,
    Icons.flag_outlined,
  ];

  // ── small builders ──

  static Widget _wrapCard(double width, Widget child) => ConstrainedBox(
    constraints: BoxConstraints(minWidth: 200, maxWidth: width),
    child: child,
  );

  Widget _sectionTitle(BuildContext context, IconData icon, String text) =>
      Padding(
        padding: const EdgeInsets.only(top: 28, bottom: 10),
        child: Row(
          children: [
            Icon(icon, size: 18, color: OracleBrand.violetSoft),
            const SizedBox(width: 10),
            Expanded(
              child: Text(text, style: Theme.of(context).textTheme.titleMedium),
            ),
          ],
        ),
      );

  Widget _card({required Widget child, EdgeInsets? margin}) => Container(
    width: double.infinity,
    margin: margin,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: OracleBrand.gray900,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: OracleBrand.gray700),
    ),
    child: child,
  );

  static Widget _chip(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: OracleBrand.violet.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      text,
      style: const TextStyle(fontSize: 11, color: OracleBrand.violetSoft),
    ),
  );

  static Widget _ctxBox(String label, Color color, IconData icon) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: color.withValues(alpha: 0.5)),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 17, color: color),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    ),
  );

  Widget _bullet(
    IconData icon,
    String text, {
    Color color = OracleBrand.gray400,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 12.5, height: 1.45),
          ),
        ),
      ],
    ),
  );
}

/// The looping ANIMATED run: the example flow's nodes light up in sequence —
/// pending → running (spinner) → done (check) — so the user SEES how a run
/// walks the graph.
class _AnimatedFlowDemo extends StatefulWidget {
  const _AnimatedFlowDemo();

  @override
  State<_AnimatedFlowDemo> createState() => _AnimatedFlowDemoState();
}

class _AnimatedFlowDemoState extends State<_AnimatedFlowDemo> {
  static const _nodes = [
    (FlowStepKind.orchestrator, 'plan'),
    (FlowStepKind.rfcCreate, 'rfc'),
    (FlowStepKind.agent, 'dev'),
    (FlowStepKind.agent, 'docs'),
    (FlowStepKind.humanGate, 'gate'),
  ];

  /// -1 = all pending; 0.._nodes.length-1 = that node running; >= length = all done.
  int _current = -1;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 950), (_) {
      if (!mounted) return;
      setState(() {
        _current++;
        if (_current > _nodes.length + 1) {
          _current = -1; // pause on "all done", reset
        }
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < _nodes.length; i++) ...[
            if (i > 0)
              AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                margin: const EdgeInsets.symmetric(horizontal: 7),
                width: 22,
                height: 2.5,
                color: i <= _current
                    ? OracleBrand.success
                    : OracleBrand.gray700,
              ),
            _node(i),
          ],
        ],
      ),
    );
  }

  Widget _node(int i) {
    final (kind, label) = _nodes[i];
    final done = _current > i || _current >= _nodes.length;
    final running = _current == i;
    final base = kindColor(kind);
    final color = done
        ? OracleBrand.success
        : running
        ? base
        : OracleBrand.gray500;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: running ? 0.18 : 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: color.withValues(alpha: running ? 0.9 : 0.45),
          width: running ? 1.8 : 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (running)
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 1.7, color: color),
            )
          else
            Icon(
              done ? Icons.check_circle : kindIcon(kind),
              size: 14,
              color: color,
            ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
          if (i == 0) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: OracleBrand.success.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                l10n.t('flows.startBadge'),
                style: const TextStyle(
                  fontSize: 9,
                  color: OracleBrand.success,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One real launch-command example: agent name + the literal CLI line.
class _CmdCard extends StatelessWidget {
  final String agent;
  final String command;
  const _CmdCard({required this.agent, required this.command});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: BoxDecoration(
        color: OracleBrand.gray950,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: OracleBrand.gray700),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            agent,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: OracleBrand.gray500,
            ),
          ),
          const SizedBox(height: 4),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SelectableText(
              '\$ $command',
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11.5,
                color: OracleBrand.gray100,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A StatusBadge clone local to the guide (avoids importing brand's widget with
/// a different name context).
class StatusBadgeLike extends StatelessWidget {
  final String label;
  final Color color;
  const StatusBadgeLike({super.key, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ConceptCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String body;
  const _ConceptCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: OracleBrand.gray900,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(height: 10),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            body,
            style: const TextStyle(
              fontSize: 12.5,
              color: OracleBrand.gray400,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _NumStep extends StatelessWidget {
  final int n;
  final String title;
  final String body;
  const _NumStep({required this.n, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: OracleBrand.gray900,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: OracleBrand.gray700),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              gradient: OracleBrand.gradient,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$n',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
          ),
          const SizedBox(height: 4),
          Text(
            body,
            style: const TextStyle(
              fontSize: 12,
              color: OracleBrand.gray400,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

/// One entry of the under-the-hood vertical timeline.
class _HoodStep extends StatelessWidget {
  final int n;
  final bool last;
  final IconData icon;
  final String title;
  final String body;
  final Widget? extra;
  const _HoodStep({
    required this.n,
    required this.last,
    required this.icon,
    required this.title,
    required this.body,
    this.extra,
  });

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: OracleBrand.violet.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: OracleBrand.violet.withValues(alpha: 0.45),
                  ),
                ),
                child: Icon(icon, size: 15, color: OracleBrand.violetSoft),
              ),
              if (!last)
                Expanded(
                  child: Container(width: 2, color: OracleBrand.gray700),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$n. $title',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13.5,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    body,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: OracleBrand.gray400,
                      height: 1.45,
                    ),
                  ),
                  if (extra != null) extra!,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FieldRef extends StatelessWidget {
  final IconData icon;
  final String name;
  final String body;
  final bool last;
  const _FieldRef({
    required this.icon,
    required this.name,
    required this.body,
    this.last = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: OracleBrand.gray500),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: OracleBrand.gray400,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CondCard extends StatelessWidget {
  final String code;
  final Color color;
  final String body;
  const _CondCard({
    required this.code,
    required this.color,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: OracleBrand.gray900,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 22, height: 3, color: color),
              const SizedBox(width: 8),
              Text(
                conditionLabel(code),
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: const TextStyle(
              fontSize: 11.5,
              color: OracleBrand.gray400,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _Check extends StatelessWidget {
  final String text;
  final bool last;
  const _Check({required this.text, this.last = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.check_box_outlined,
            size: 17,
            color: OracleBrand.success,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}
