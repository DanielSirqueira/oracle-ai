/// Task lifecycle status (matches the `tasks.status` CHECK constraint).
enum TaskStatus {
  backlog('backlog'),
  ready('ready'),
  running('running'),
  blocked('blocked'),
  done('done'),
  cancelled('cancelled');

  /// Value persisted in the database.
  final String code;
  const TaskStatus(this.code);

  static TaskStatus parse(String code) => values.firstWhere(
    (e) => e.code == code,
    orElse: () => TaskStatus.backlog,
  );
}
