import 'package:oracle_core/oracle_core.dart';

/// Query for [RulesForTaskUsecase]: the applicable rules for a task in a
/// project, resolving organization→project inheritance (project rules override
/// organization rules with the same key).
class RulesForTaskQuery {
  /// Project the task runs in (its organization's rules are inherited).
  final IdVO projectId;

  /// Optional module the task runs in — its rules override the project's, whose
  /// rules override the organization's (most specific wins).
  final IdVO? moduleId;

  /// Optional scope filter (e.g. `controllers`, `design-system`).
  final String? scope;

  final int limit;

  const RulesForTaskQuery({required this.projectId, this.moduleId, this.scope, this.limit = 50});
}
