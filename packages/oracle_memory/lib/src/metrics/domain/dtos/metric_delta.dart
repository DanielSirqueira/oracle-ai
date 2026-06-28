import 'package:oracle_core/oracle_core.dart';

/// An incremental update to a session's metrics — ADDED to the existing row
/// (upsert) so events accumulate as they arrive.
class MetricDelta {
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

  const MetricDelta({
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
  });
}
