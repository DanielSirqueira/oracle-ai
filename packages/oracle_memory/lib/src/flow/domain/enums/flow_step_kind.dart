/// The executor a step drives (matches the `flow_steps.kind` CHECK constraint).
///
/// - [agent] — a headless coding agent loop (the general case).
/// - [orchestrator] — same, but with the flow's orchestrator agent (plan/decide).
/// - [rfcCreate] — an agent PUBLISHES the RFC (oracle_rfc_open) for the task.
/// - [rfcReview] — agents review the RFC with evidence-grounded findings.
/// - [rfcConsolidate] — an agent resolves the round's findings, REVISES the RFC
///   and writes the implementation plan to the blackboard.
/// - [rfcGate] — DETERMINISTIC round gate (no LLM): queries the RFC engine and
///   routes by verdict — `continuar` (new round), `concluir` (no blocking/new
///   findings) or `limite` (max rounds reached).
/// - [command] — a deterministic command (build, deploy) — no LLM.
/// - [humanGate] — parks the run until approval in the Studio.
enum FlowStepKind {
  agent('agent'),
  orchestrator('orchestrator'),

  /// A generic DECISION node: the agent evaluates whatever the step says and
  /// MUST write blackboard key "verdict" with exactly one of the step's
  /// verdict-edge values — the runner routes on it (2..N branches, reusable).
  decision('decision'),
  rfcCreate('rfc_create'),
  rfcReview('rfc_review'),
  rfcConsolidate('rfc_consolidate'),
  rfcGate('rfc_gate'),

  /// Executes ANOTHER flow as a child run, inline, in the same workspace
  /// (n8n's "Execute Workflow"). Target via `config.flowKey`; blackboard is
  /// copied down and merged back up. Max nesting depth: 3.
  subflow('subflow'),

  /// Deterministic fan-in barrier. The scheduler waits until every ACTIVE
  /// incoming branch has finished, records a zero-cost step, then continues.
  join('join'),
  command('command'),
  humanGate('human_gate');

  /// Value persisted in the database.
  final String code;
  const FlowStepKind(this.code);

  static FlowStepKind parse(String code) => values.firstWhere(
    (e) => e.code == code,
    orElse: () => FlowStepKind.agent,
  );
}
