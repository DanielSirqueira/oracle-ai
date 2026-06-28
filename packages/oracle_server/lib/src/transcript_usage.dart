import 'dart:convert';
import 'dart:io';

/// Token usage of one assistant turn.
class TurnUsage {
  final int input;
  final int output;
  final int cacheCreation;
  final int cacheRead;
  const TurnUsage({this.input = 0, this.output = 0, this.cacheCreation = 0, this.cacheRead = 0});
  static const zero = TurnUsage();
}

/// Reads the agent transcript (JSONL) and returns the usage of the LAST turn
/// that reported one. **Never throws** — returns [TurnUsage.zero] on any problem
/// (missing file, unknown format). Called once per Stop hook (one completed
/// turn), so accumulating these per-turn deltas yields the true session total
/// even if a later compaction truncates the file.
TurnUsage lastTurnUsage(String transcriptPath) {
  try {
    if (transcriptPath.trim().isEmpty) return TurnUsage.zero;
    final file = File(transcriptPath);
    if (!file.existsSync()) return TurnUsage.zero;
    for (final line in file.readAsLinesSync().reversed) {
      final usage = _usageOf(line);
      if (usage != null) return usage;
    }
    return TurnUsage.zero;
  } catch (_) {
    return TurnUsage.zero;
  }
}

TurnUsage? _usageOf(String line) {
  if (line.trim().isEmpty) return null;
  try {
    final usage = _findUsage(jsonDecode(line));
    if (usage == null) return null;
    int n(String k) => (usage[k] as num?)?.toInt() ?? 0;
    return TurnUsage(
      input: n('input_tokens'),
      output: n('output_tokens'),
      cacheCreation: n('cache_creation_input_tokens'),
      cacheRead: n('cache_read_input_tokens'),
    );
  } catch (_) {
    return null;
  }
}

/// Finds a `usage` object at the top level or under `message` (the two shapes
/// the transcript uses), tolerating anything else.
Map<String, dynamic>? _findUsage(dynamic obj) {
  if (obj is! Map) return null;
  if (obj['usage'] is Map) return (obj['usage'] as Map).cast<String, dynamic>();
  final msg = obj['message'];
  if (msg is Map && msg['usage'] is Map) return (msg['usage'] as Map).cast<String, dynamic>();
  return null;
}
