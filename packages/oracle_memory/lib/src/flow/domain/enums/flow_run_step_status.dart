/// Status of one iteration of one step (matches `flow_run_steps.status`).
enum FlowRunStepStatus {
  running('running'),
  verifying('verifying'),
  passed('passed'),
  failed('failed'),
  skipped('skipped'),
  parked('parked'),
  abandoned('abandoned');

  /// Value persisted in the database.
  final String code;
  const FlowRunStepStatus(this.code);

  static FlowRunStepStatus parse(String code) => values.firstWhere(
    (e) => e.code == code,
    orElse: () => FlowRunStepStatus.running,
  );
}
