import 'package:oracle_core/oracle_core.dart';

/// Accumulated token & event counts for one agent session under one experiment
/// [label]. Built incrementally from the lifecycle hooks.
class SessionMetricEntity {
  final IdVO id;
  final IdVO projectId;
  final String externalId;
  final String label;
  final int inputTokens;
  final int outputTokens;
  final int cacheCreationTokens;
  final int cacheReadTokens;
  final int compactions;
  final int toolUses;
  final int turns;
  final DateTime? updatedAt;

  const SessionMetricEntity({
    required this.id,
    required this.projectId,
    required this.externalId,
    this.label = 'default',
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.cacheCreationTokens = 0,
    this.cacheReadTokens = 0,
    this.compactions = 0,
    this.toolUses = 0,
    this.turns = 0,
    this.updatedAt,
  });

  /// All input the model processed (fresh + cache writes + cache reads).
  int get totalInputTokens => inputTokens + cacheCreationTokens + cacheReadTokens;

  /// Fraction of input served from the (cheap) prompt cache — the key
  /// efficiency signal. Higher is cheaper.
  double get cacheReadRatio =>
      totalInputTokens == 0 ? 0 : cacheReadTokens / totalInputTokens;
}
