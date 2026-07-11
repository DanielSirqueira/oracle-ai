import 'package:oracle_core/oracle_core.dart';

/// Query for [RulesForTaskUsecase]: the applicable rules for a task in a
/// project, resolving organization→project inheritance (project rules override
/// organization rules with the same key).
class RulesForTaskQuery {
  /// Project the task runs in (its organization's rules are inherited).
  final IdVO projectId;

  /// Optional scope filter (e.g. `controllers`, `design-system`).
  final String? scope;

  final int limit;

  const RulesForTaskQuery({required this.projectId, this.scope, this.limit = 50});
}
