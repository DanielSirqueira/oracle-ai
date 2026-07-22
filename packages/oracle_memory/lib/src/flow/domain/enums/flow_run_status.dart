/// Flow run lifecycle status (matches the `flow_runs.status` CHECK constraint).
///
/// `queued → running`, branching to `awaiting_human` (a human_gate / product
/// decision) or `paused`, `stalled` (budget / no-progress), and terminating in
/// `completed`, `failed` or `cancelled`.
enum FlowRunStatus {
  queued('queued'),
  running('running'),
  awaitingHuman('awaiting_human'),
  paused('paused'),
  stalled('stalled'),
  completed('completed'),
  failed('failed'),
  cancelled('cancelled');

  /// Value persisted in the database.
  final String code;
  const FlowRunStatus(this.code);

  /// A run in one of these states will never advance again on its own.
  bool get isTerminal =>
      this == completed || this == failed || this == cancelled;

  static FlowRunStatus parse(String code) => values.firstWhere(
    (e) => e.code == code,
    orElse: () => FlowRunStatus.queued,
  );
}
