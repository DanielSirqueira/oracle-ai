import 'dart:io';

import 'step_launcher.dart';

/// One diagnostic result. [detail] is language-neutral data (a path, an exit
/// code, an error) — the UI wraps it with localized labels.
class AgentCheck {
  final bool ok;
  final String detail;
  const AgentCheck(this.ok, this.detail);
}

/// The health of one agent integration for a given repo:
/// - [cli] — the agent's CLI resolves to a callable executable;
/// - [mcp] — the Oracle MCP server is configured for it (required: the step
///   protocol tools live there);
/// - [hooks] — lifecycle hooks are configured (optional: capture/session-link);
/// - [receiver] — the hook receiver answers /health (optional: capture);
/// - [sandbox] — the agent's own sandbox can spawn shell commands (advisory:
///   MCP still works when it fails, but every shell call inside a step dies).
class AgentHealth {
  final String agent;
  final AgentCheck cli;
  final AgentCheck mcp;
  final AgentCheck hooks;
  final AgentCheck receiver;
  final AgentCheck sandbox;
  const AgentHealth({
    required this.agent,
    required this.cli,
    required this.mcp,
    required this.hooks,
    required this.receiver,
    this.sandbox = const AgentCheck(true, '—'),
  });

  /// The flow can RUN with this agent (launch + step tools).
  bool get ready => cli.ok && mcp.ok;

  /// Everything, including capture and the agent's shell sandbox, is wired.
  bool get fullyWired => ready && hooks.ok && receiver.ok && sandbox.ok;
}

/// Checks whether an agent is actually able to run a flow step on this machine:
/// callable CLI, Oracle MCP configured (project or global file), hooks present,
/// hook receiver reachable — plus a real smoke test that launches the CLI with
/// a trivial prompt. Pure I/O checks; no LLM keys are ever read.
class AgentDoctor {
  final String? repoRoot;
  final String hookHost;
  final int hookPort;
  final StepLauncher _launcher;

  AgentDoctor({
    this.repoRoot,
    this.hookHost = '127.0.0.1',
    this.hookPort = 47500,
    StepLauncher? launcher,
  }) : _launcher = launcher ?? StepLauncher();

  static String get _home =>
      Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? '';

  Future<AgentHealth> check(String agent) async {
    final cli = await _checkCli(agent);
    final mcp = _checkMcp(agent);
    final hooks = _checkHooks(agent);
    final receiver = await _checkReceiver();
    final sandbox = _checkSandbox(agent);
    return AgentHealth(
      agent: agent,
      cli: cli,
      mcp: mcp,
      hooks: hooks,
      receiver: receiver,
      sandbox: sandbox,
    );
  }

  /// Launches the agent CLI headless with a trivial prompt and reports whether
  /// it completed. This is the "will it actually run?" proof. It runs in the
  /// PROJECT's repo root when known — a temp-dir cwd would make the hooks
  /// auto-register that temp dir as a bogus project (and the real cwd also
  /// exercises the project's `.mcp.json`, closer to a real step).
  Future<AgentCheck> smokeTest(String agent, {int timeoutMinutes = 4}) async {
    final root = repoRoot;
    final useRepo =
        root != null && root.trim().isNotEmpty && Directory(root).existsSync();
    final dir = useRepo
        ? null
        : await Directory.systemTemp.createTemp('oracle_smoke_');
    final sw = Stopwatch()..start();
    try {
      final result = await _launcher.launch(
        agent: agent,
        prompt: 'Reply with exactly: OK',
        workdir: useRepo ? root : dir!.path,
        timeoutMinutes: timeoutMinutes,
      );
      sw.stop();
      final secs = (sw.elapsedMilliseconds / 1000).toStringAsFixed(1);
      if (result.timedOut) {
        return AgentCheck(false, 'timeout ${timeoutMinutes}m');
      }
      if (!result.ok) {
        final err = result.stderr.trim();
        return AgentCheck(
          false,
          'exit ${result.exitCode}${err.isEmpty ? '' : ' — ${_clip(err)}'}',
        );
      }
      return AgentCheck(true, '${secs}s');
    } on StepLauncherException catch (e) {
      return AgentCheck(false, e.message);
    } finally {
      try {
        await dir?.delete(recursive: true);
      } catch (_) {
        /* temp cleanup is best-effort */
      }
    }
  }

  // ── individual checks ──

  Future<AgentCheck> _checkCli(String agent) async {
    final executable = StepLauncher.executableFor(agent);
    try {
      // `where` alone is insufficient: WindowsApps may expose a path whose ACL
      // denies child processes. Actually execute the lightweight version flag.
      final result = await Process.run(
        executable,
        const ['--version'],
        runInShell: true,
        environment: StepLauncher.processEnvironmentFor(agent),
      ).timeout(const Duration(seconds: 15));
      if (result.exitCode == 0) {
        return AgentCheck(true, executable);
      }
      final detail = '${result.stderr}'.trim();
      return AgentCheck(false, detail.isEmpty ? executable : _clip(detail));
    } catch (_) {
      return AgentCheck(false, executable);
    }
  }

  AgentCheck _checkMcp(String agent) {
    // Candidate config files per agent (project first, then global), and the
    // marker that proves the Oracle server is registered in them.
    final h = _home;
    final r = repoRoot;
    final candidates = switch (agent) {
      'claude-code' => [if (r != null) '$r/.mcp.json', '$h/.claude.json'],
      'codex' => ['$h/.codex/config.toml'],
      'gemini' => [
        if (r != null) '$r/.gemini/settings.json',
        '$h/.gemini/settings.json',
      ],
      'cursor' => [if (r != null) '$r/.cursor/mcp.json', '$h/.cursor/mcp.json'],
      'copilot' => [if (r != null) '$r/.vscode/mcp.json'],
      _ => const <String>[],
    };
    for (final path in candidates) {
      if (_fileContains(path, 'oracle-ai') ||
          _fileContains(path, 'oracle_ai')) {
        if (agent == 'codex') {
          final content = _readFile(path);
          if (!codexMcpConfigReady(content)) {
            return AgentCheck(
              false,
              '$path — oracle-ai sem required=true e aprovação padrão headless',
            );
          }
        }
        return AgentCheck(true, path);
      }
    }
    return AgentCheck(false, candidates.isEmpty ? '—' : candidates.first);
  }

  AgentCheck _checkHooks(String agent) {
    final h = _home;
    final r = repoRoot;
    final candidates = switch (agent) {
      // Native HTTP hooks — the settings carry the receiver URL (/hook).
      'claude-code' => ['$h/.claude/settings.json'],
      // Bridge hooks — the config carries the forward-hook command.
      'codex' => ['$h/.codex/hooks.json'],
      'gemini' => [
        if (r != null) '$r/.gemini/settings.json',
        '$h/.gemini/settings.json',
      ],
      'cursor' => [
        if (r != null) '$r/.cursor/hooks.json',
        '$h/.cursor/hooks.json',
      ],
      _ => const <String>[],
    };
    final marker = agent == 'claude-code' ? '/hook' : 'forward-hook';
    for (final path in candidates) {
      if (_fileContains(path, marker)) return AgentCheck(true, path);
    }
    return AgentCheck(false, candidates.isEmpty ? '—' : candidates.first);
  }

  /// Codex/Windows: its sandbox spawns shell commands with a restricted token
  /// (`CreateProcessAsUserW`). When `pwsh.exe` resolves to the Microsoft Store
  /// alias under `WindowsApps`, that directory's ACL denies the restricted
  /// token and EVERY shell call inside a step fails with "Acesso negado" —
  /// while MCP keeps working, which makes the failure hard to attribute.
  /// Cleaning the child PATH does not help: the Codex app runtime resolves the
  /// alias from the login environment. The fix is machine-level (install the
  /// MSI PowerShell 7, which lands in the system PATH ahead of the user's
  /// WindowsApps entry, or disable the Store alias).
  AgentCheck _checkSandbox(String agent) {
    if (agent != 'codex' || !Platform.isWindows) {
      return const AgentCheck(true, '—');
    }
    final localAppData = Platform.environment['LOCALAPPDATA'] ?? '';
    final alias = '$localAppData\\Microsoft\\WindowsApps\\pwsh.exe';
    final aliasExists = localAppData.isNotEmpty && File(alias).existsSync();
    final nonStore = _nonStorePwsh();
    final issue = windowsStorePwshIssue(
      storeAliasExists: aliasExists,
      nonStorePwshExists: nonStore != null,
    );
    if (issue != null) return AgentCheck(false, alias);
    return AgentCheck(true, nonStore ?? 'powershell.exe');
  }

  /// A pwsh install OUTSIDE the Store (MSI/winget machine scope) — the only
  /// kind the Codex Windows sandbox can execute. Null when absent.
  static String? _nonStorePwsh() {
    for (final programFiles in [
      Platform.environment['ProgramFiles'],
      Platform.environment['ProgramFiles(x86)'],
    ]) {
      if (programFiles == null || programFiles.isEmpty) continue;
      final root = Directory('$programFiles\\PowerShell');
      if (!root.existsSync()) continue;
      try {
        for (final dir in root.listSync().whereType<Directory>()) {
          final exe = File('${dir.path}\\pwsh.exe');
          if (exe.existsSync()) return exe.path;
        }
      } catch (_) {
        /* unreadable dir — treat as absent */
      }
    }
    return null;
  }

  /// Pure decision behind [_checkSandbox], for tests: the trap exists when the
  /// Store alias is the ONLY pwsh on the machine.
  static String? windowsStorePwshIssue({
    required bool storeAliasExists,
    required bool nonStorePwshExists,
  }) {
    if (!storeAliasExists || nonStorePwshExists) return null;
    return 'pwsh.exe resolves to the Microsoft Store alias (WindowsApps) — '
        'the Codex sandbox cannot execute it (CreateProcessAsUserW: access '
        'denied)';
  }

  Future<AgentCheck> _checkReceiver() async {
    final url = 'http://$hookHost:$hookPort/health';
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 2);
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close().timeout(
        const Duration(seconds: 3),
      );
      await response.drain<void>();
      client.close(force: true);
      return AgentCheck(response.statusCode == 200, '$hookHost:$hookPort');
    } catch (_) {
      return AgentCheck(false, '$hookHost:$hookPort');
    }
  }

  static bool _fileContains(String path, String marker) {
    try {
      final file = File(path);
      if (!file.existsSync()) return false;
      return file.readAsStringSync().contains(marker);
    } catch (_) {
      return false;
    }
  }

  static String _readFile(String path) {
    try {
      final file = File(path);
      return file.existsSync() ? file.readAsStringSync() : '';
    } catch (_) {
      return '';
    }
  }

  /// A mere `command` entry is not enough for a non-interactive flow. Without
  /// these settings Codex asks for approval, but `codex exec -a never` has no
  /// human at that boundary and reports `user cancelled MCP tool call`.
  static bool codexMcpConfigReady(String content) {
    final header = RegExp(
      r'^\s*\[mcp_servers\.oracle-ai\]\s*$',
      multiLine: true,
    ).firstMatch(content);
    if (header == null) return false;
    final tail = content.substring(header.end);
    final nextHeader = RegExp(r'^\s*\[', multiLine: true).firstMatch(tail);
    final block = nextHeader == null
        ? tail
        : tail.substring(0, nextHeader.start);
    return RegExp(
          r'^\s*required\s*=\s*true\s*$',
          multiLine: true,
          caseSensitive: false,
        ).hasMatch(block) &&
        RegExp(
          r'''^\s*default_tools_approval_mode\s*=\s*["']approve["']\s*$''',
          multiLine: true,
          caseSensitive: false,
        ).hasMatch(block);
  }

  static String _clip(String s, [int max = 160]) =>
      s.length <= max ? s : '${s.substring(0, max)}…';
}
