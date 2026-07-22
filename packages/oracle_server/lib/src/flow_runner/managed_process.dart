import 'dart:async';
import 'dart:convert';
import 'dart:io';

class ManagedProcessResult {
  final int exitCode;
  final String stdout;
  final String stderr;
  final bool timedOut;
  final bool cancelled;

  const ManagedProcessResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    this.timedOut = false,
    this.cancelled = false,
  });
}

/// Runs a process with bounded output and terminates its whole process tree on
/// timeout/cancellation. This prevents verifier shells and agent descendants
/// from surviving after a run is stopped.
class ManagedProcess {
  static const _maxOutputChars = 8 * 1024 * 1024;

  static Future<ManagedProcessResult> run(
    String executable,
    List<String> arguments, {
    required String workdir,
    bool runInShell = false,
    Map<String, String>? environment,
    String? stdinText,
    Duration? timeout,
    Future<bool> Function()? isCancelled,
  }) async {
    final process = await Process.start(
      executable,
      arguments,
      workingDirectory: workdir,
      runInShell: runInShell,
      environment: environment,
    );
    if (stdinText != null) {
      try {
        process.stdin.write(stdinText);
        await process.stdin.flush();
      } catch (_) {
        // A fast-failing CLI can close stdin before the writer finishes.
      } finally {
        await process.stdin.close().catchError((_) {});
      }
    }

    final out = _BoundedText(_maxOutputChars);
    final err = _BoundedText(_maxOutputChars);
    final outDone = process.stdout.transform(utf8.decoder).forEach(out.add);
    final errDone = process.stderr.transform(utf8.decoder).forEach(err.add);
    final started = DateTime.now();
    var timedOut = false;
    var cancelled = false;
    int? exitCode;
    final exitFuture = process.exitCode.then((value) => exitCode = value);

    while (exitCode == null) {
      await Future.any<void>([
        exitFuture,
        Future<void>.delayed(const Duration(seconds: 1)),
      ]);
      if (exitCode != null) break;
      if (timeout != null && DateTime.now().difference(started) >= timeout) {
        timedOut = true;
        await _killTree(process);
        break;
      }
      if (isCancelled != null && await isCancelled()) {
        cancelled = true;
        await _killTree(process);
        break;
      }
    }
    await exitFuture.timeout(const Duration(seconds: 10), onTimeout: () => 124);
    await Future.wait([outDone, errDone]).catchError((_) => <void>[]);
    return ManagedProcessResult(
      exitCode: timedOut || cancelled ? 124 : (exitCode ?? 124),
      stdout: out.value,
      stderr: err.value,
      timedOut: timedOut,
      cancelled: cancelled,
    );
  }

  static Future<void> _killTree(Process process) async {
    if (Platform.isWindows) {
      try {
        final killed = await Process.run('taskkill', [
          '/PID',
          '${process.pid}',
          '/T',
          '/F',
        ], runInShell: true).timeout(const Duration(seconds: 8));
        if (killed.exitCode != 0) process.kill();
      } catch (_) {
        process.kill();
      }
      return;
    }
    try {
      await Process.run('pkill', ['-TERM', '-P', '${process.pid}'])
          .timeout(const Duration(seconds: 4));
    } catch (_) {
      // Parent termination below remains the portable fallback.
    }
    process.kill(ProcessSignal.sigterm);
    await Future<void>.delayed(const Duration(seconds: 2));
    process.kill(ProcessSignal.sigkill);
  }
}

class _BoundedText {
  final int limit;
  final StringBuffer _buffer = StringBuffer();
  int _length = 0;
  bool _truncated = false;

  _BoundedText(this.limit);

  void add(String chunk) {
    if (_length >= limit) {
      _truncated = true;
      return;
    }
    final remaining = limit - _length;
    final accepted = chunk.length <= remaining
        ? chunk
        : chunk.substring(0, remaining);
    _buffer.write(accepted);
    _length += accepted.length;
    if (accepted.length != chunk.length) _truncated = true;
  }

  String get value => _truncated
      ? '${_buffer.toString()}\n[output truncated at $limit characters]'
      : _buffer.toString();
}
