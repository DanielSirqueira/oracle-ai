import 'dart:convert';

import 'managed_process.dart';

/// The result of running a step's verifiers.
class VerifierResult {
  final bool passed;
  final String details;

  const VerifierResult({required this.passed, required this.details});

  Map<String, dynamic> toJson() => {'passed': passed, 'details': details};
}

/// Runs a step's `exit_criteria` OUTSIDE the agent, in the run's worktree — the
/// agent cannot self-approve. `exit_criteria` is `{"commands": ["dart analyze",
/// "dart test"], ...}`; every command must exit 0. Empty criteria passes (a step
/// with no objective check advances on its report alone).
class Verifier {
  Future<VerifierResult> run({
    required String exitCriteriaJson,
    required String workdir,
    int timeoutMinutes = 15,
    Future<bool> Function()? isCancelled,
  }) async {
    Map<String, dynamic> criteria;
    try {
      final decoded = jsonDecode(exitCriteriaJson);
      criteria = decoded is Map<String, dynamic> ? decoded : const {};
    } catch (error) {
      return VerifierResult(
        passed: false,
        details: 'invalid exit criteria JSON: $error',
      );
    }

    final commands =
        (criteria['commands'] as List?)
            ?.map((e) => e.toString())
            .where((c) => c.trim().isNotEmpty)
            .toList() ??
        const <String>[];
    if (commands.isEmpty) {
      return const VerifierResult(
        passed: true,
        details: 'no verifier commands',
      );
    }

    final logs = StringBuffer();
    for (final cmd in commands) {
      final result = await ManagedProcess.run(
        cmd,
        const [],
        workdir: workdir,
        runInShell: true,
        timeout: timeoutMinutes > 0 ? Duration(minutes: timeoutMinutes) : null,
        isCancelled: isCancelled,
      );
      logs.writeln('\$ $cmd -> exit ${result.exitCode}');
      if (result.timedOut) logs.writeln('verifier timed out');
      if (result.cancelled) logs.writeln('verifier cancelled');
      if (result.exitCode != 0) {
        logs.writeln(_tail(result.stdout));
        logs.writeln(_tail(result.stderr));
        return VerifierResult(passed: false, details: logs.toString());
      }
    }
    return VerifierResult(passed: true, details: logs.toString());
  }

  static String _tail(String s, [int max = 2000]) =>
      s.length <= max ? s : '…${s.substring(s.length - max)}';
}
