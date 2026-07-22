import 'package:flutter/material.dart';
import 'package:oracle_memory/oracle_memory.dart';

import '../../core/brand.dart';
import '../../core/l10n.dart';

/// Friendly, localized labels for every Loop Engineering enum — the user never
/// sees a raw database code. Each helper maps enum → l10n key.

// ── step kind ──

String kindLabel(FlowStepKind k) => l10n.t('flowkind.${k.code}');
String kindDescription(FlowStepKind k) => l10n.t('flowkindDesc.${k.code}');

IconData kindIcon(FlowStepKind k) {
  switch (k) {
    case FlowStepKind.agent:
      return Icons.smart_toy_outlined;
    case FlowStepKind.orchestrator:
      return Icons.hub_outlined;
    case FlowStepKind.decision:
      return Icons.alt_route;
    case FlowStepKind.rfcCreate:
      return Icons.post_add_outlined;
    case FlowStepKind.rfcReview:
      return Icons.reviews_outlined;
    case FlowStepKind.rfcConsolidate:
      return Icons.fact_check_outlined;
    case FlowStepKind.rfcGate:
      return Icons.autorenew;
    case FlowStepKind.subflow:
      return Icons.account_tree_outlined;
    case FlowStepKind.join:
      return Icons.call_merge;
    case FlowStepKind.command:
      return Icons.terminal_outlined;
    case FlowStepKind.humanGate:
      return Icons.pan_tool_outlined;
  }
}

Color kindColor(FlowStepKind k) {
  switch (k) {
    case FlowStepKind.agent:
      return OracleBrand.violet;
    case FlowStepKind.orchestrator:
      return OracleBrand.violetSoft;
    case FlowStepKind.decision:
      return OracleBrand.warning;
    case FlowStepKind.rfcCreate:
    case FlowStepKind.rfcReview:
    case FlowStepKind.rfcConsolidate:
    case FlowStepKind.rfcGate:
      return OracleBrand.blue;
    case FlowStepKind.subflow:
      return OracleBrand.success;
    case FlowStepKind.join:
      return OracleBrand.blue;
    case FlowStepKind.command:
      return OracleBrand.gray500;
    case FlowStepKind.humanGate:
      return OracleBrand.warning;
  }
}

// ── agents (display names are product names — not localized) ──

/// Only agents with a real headless adapter in [StepLauncher]. Showing an
/// integration-only host here would let users save a process that can never run.
const agentIds = ['claude-code', 'codex', 'gemini', 'cursor'];

/// CLI-safe model SUGGESTIONS per agent (July 2026, from each CLI's own docs).
/// The model field is EDITABLE — catalogs change monthly, so these are hints,
/// never a cage; any id the CLI accepts can be typed. Empty = agent default.
/// - claude-code: `--model` takes an alias (fable/opus/sonnet/haiku) or a full
///   model name (claude --help).
/// - codex: `-m` (post-sunset ids, developers.openai.com config reference).
/// - gemini: `-m` (geminicli.com model docs, Gemini 3 preview + 2.5).
/// - cursor: `--model`; valid ids via `cursor-agent --list-models`.
List<String> modelOptions(String agent) => switch (agent) {
  'claude-code' => const ['fable', 'opus', 'sonnet', 'haiku'],
  'codex' => const [
    'gpt-5.5',
    'gpt-5.4',
    'gpt-5.4-mini',
    'gpt-5.3-codex',
    'gpt-5.2',
  ],
  'gemini' => const [
    'gemini-3-pro-preview',
    'gemini-3-flash-preview',
    'gemini-2.5-pro',
    'gemini-2.5-flash',
  ],
  'cursor' => const ['composer-1', 'sonnet-4.5', 'gpt-5', 'opus'],
  _ => const [],
};

/// Reasoning-effort levels per agent CLI (empty = the CLI has no such flag).
/// - claude-code: `--effort low|medium|high|xhigh|max` (claude --help).
/// - codex: `-c model_reasoning_effort=minimal|low|medium|high|xhigh`
///   (xhigh is model-dependent — developers.openai.com config reference).
/// - gemini / cursor: no reasoning-effort option exposed on the CLI.
List<String> effortOptions(String agent) => switch (agent) {
  'claude-code' => const ['low', 'medium', 'high', 'xhigh', 'max'],
  'codex' => const ['minimal', 'low', 'medium', 'high', 'xhigh'],
  _ => const [],
};

String effortLabel(String code) => l10n.t('floweffort.$code');

String agentLabel(String id) => switch (id) {
  'claude-code' => 'Claude Code',
  'codex' => 'Codex',
  'gemini' => 'Gemini CLI',
  'cursor' => 'Cursor',
  'copilot' => 'Copilot',
  _ => id,
};

// ── run status ──

String runStatusLabel(FlowRunStatus s) => l10n.t('runst.${s.code}');

Color runStatusColor(FlowRunStatus s) {
  switch (s) {
    case FlowRunStatus.queued:
      return OracleBrand.gray500;
    case FlowRunStatus.running:
      return OracleBrand.violet;
    case FlowRunStatus.awaitingHuman:
    case FlowRunStatus.paused:
    case FlowRunStatus.stalled:
      return OracleBrand.warning;
    case FlowRunStatus.completed:
      return OracleBrand.success;
    case FlowRunStatus.failed:
      return OracleBrand.error;
    case FlowRunStatus.cancelled:
      return OracleBrand.gray500;
  }
}

IconData runStatusIcon(FlowRunStatus s) {
  switch (s) {
    case FlowRunStatus.queued:
      return Icons.schedule;
    case FlowRunStatus.running:
      return Icons.play_circle;
    case FlowRunStatus.awaitingHuman:
      return Icons.pan_tool_outlined;
    case FlowRunStatus.paused:
      return Icons.pause_circle_outline;
    case FlowRunStatus.stalled:
      return Icons.warning_amber_outlined;
    case FlowRunStatus.completed:
      return Icons.check_circle;
    case FlowRunStatus.failed:
      return Icons.error_outline;
    case FlowRunStatus.cancelled:
      return Icons.cancel_outlined;
  }
}

// ── task status ──

String taskStatusLabel(TaskStatus s) => l10n.t('taskst.${s.code}');

Color taskStatusColor(TaskStatus s) {
  switch (s) {
    case TaskStatus.backlog:
      return OracleBrand.gray500;
    case TaskStatus.ready:
      return OracleBrand.blue;
    case TaskStatus.running:
      return OracleBrand.violet;
    case TaskStatus.blocked:
      return OracleBrand.warning;
    case TaskStatus.done:
      return OracleBrand.success;
    case TaskStatus.cancelled:
      return OracleBrand.error;
  }
}

// ── run-step status ──

String stepStatusLabel(FlowRunStepStatus s) => l10n.t('stepst.${s.code}');

Color stepStatusColor(FlowRunStepStatus s) {
  switch (s) {
    case FlowRunStepStatus.running:
    case FlowRunStepStatus.verifying:
      return OracleBrand.violet;
    case FlowRunStepStatus.passed:
      return OracleBrand.success;
    case FlowRunStepStatus.failed:
      return OracleBrand.error;
    case FlowRunStepStatus.skipped:
      return OracleBrand.gray500;
    case FlowRunStepStatus.parked:
      return OracleBrand.warning;
    case FlowRunStepStatus.abandoned:
      return OracleBrand.gray500;
  }
}

// ── edge condition / on-fail ──

const edgeConditions = ['success', 'failure', 'verdict', 'always'];
String conditionLabel(String code) => l10n.t('flowcond.$code');

const onFailOptions = ['park', 'halt', 'continue'];
String onFailLabel(String code) => l10n.t('flowfail.$code');

// ── run-event kinds (timeline) ──

String eventKindLabel(String code) {
  final key = 'flowev.$code';
  final t = l10n.t(key);
  return t == key ? code : t;
}
