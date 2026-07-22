import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'managed_process.dart';

/// The outcome of launching one headless agent process. [tokensUsed] and
/// [sessionExternalId] are parsed best-effort from the harness's structured
/// output (claude `--output-format json`, codex JSONL) — 0 / null when the shape
/// is unknown.
class StepLaunchResult {
  final int exitCode;
  final String stdout;
  final String stderr;
  final bool timedOut;
  final int tokensUsed;
  final String? sessionExternalId;

  /// The agent's FINAL message text (claude `result`, codex agent_message) —
  /// best-effort; used so a protocol-only retry can reuse the finished work
  /// instead of redoing it. Empty when the shape is unknown.
  final String resultText;

  /// The exact CLI invocation, with the (huge) prompt replaced by `<prompt>` —
  /// shown to the user in the run monitor.
  final String commandLine;

  const StepLaunchResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    this.timedOut = false,
    this.tokensUsed = 0,
    this.sessionExternalId,
    this.resultText = '',
    this.commandLine = '',
  });

  bool get ok => exitCode == 0 && !timedOut;
}

/// Launches a coding agent (harness) in non-interactive / headless mode inside a
/// run's worktree, with the prompt composed by the runner. The adapter table is
/// DATA, not logic — one entry per harness (mirrors the installer's
/// `agentIntegrations`). Phase 1 ships claude-code + codex + gemini + cursor; an
/// unknown agent fails cleanly so the step can be parked, never silently skipped.
class StepLauncher {
  /// Resolves the public CLI command. Agent integrations depend on their
  /// supported command (`codex`, `claude`, `gemini`, etc.), not on an internal
  /// binary hidden inside a package. Explicit overrides remain available for
  /// managed enterprise installations.
  static String executableFor(String agent) {
    final overrideKey = switch (agent) {
      'claude-code' || 'claude' => 'ORACLE_CLAUDE_PATH',
      'codex' => 'ORACLE_CODEX_PATH',
      'gemini' => 'ORACLE_GEMINI_PATH',
      'cursor' => 'ORACLE_CURSOR_PATH',
      _ => '',
    };
    final override = overrideKey.isEmpty
        ? null
        : Platform.environment[overrideKey]?.trim();
    if (override != null && override.isNotEmpty) return override;

    return switch (agent) {
      'claude-code' || 'claude' => 'claude',
      'codex' => 'codex',
      'gemini' => 'gemini',
      'cursor' => 'cursor-agent',
      _ => agent,
    };
  }

  Future<StepLaunchResult> launch({
    required String agent,
    String? model,
    String? effort,
    required String prompt,
    required String workdir,
    int timeoutMinutes = 30,
    Map<String, String> environment = const {},
    Future<bool> Function()? isCancelled,
    String permissionsJson = '{}',
    String? resumeSessionId,
    String? newSessionId,
    String? codexSandbox,
  }) async {
    final argv = _argv(
      agent: agent,
      model: _normalizeModel(agent, model),
      effort: _normalizeEffort(agent, effort),
      workdir: workdir,
      permissionsJson: permissionsJson,
      resumeSessionId: resumeSessionId,
      newSessionId: newSessionId,
      codexSandbox: codexSandbox,
    );
    if (argv == null) {
      throw StepLauncherException('No headless adapter for agent "$agent"');
    }
    final commandLine = '${_displayCommand(argv)}  (prompt via stdin)';
    final processEnvironment = processEnvironmentFor(agent, environment);

    final ManagedProcessResult process;
    try {
      process = await ManagedProcess.run(
        argv.first,
        argv.sublist(1),
        workdir: workdir,
        runInShell: true,
        // ORACLE_* attribution vars — inherited by the agent AND by the Oracle
        // MCP server the agent spawns, pinning tool calls to the right project.
        environment: processEnvironment.isEmpty ? null : processEnvironment,
        stdinText: prompt,
        timeout: timeoutMinutes > 0 ? Duration(minutes: timeoutMinutes) : null,
        isCancelled: isCancelled,
      );
    } on ProcessException catch (e) {
      throw StepLauncherException('Failed to launch "$agent": ${e.message}');
    }

    final usage = parseStructuredOutput(agent, process.stdout);
    return StepLaunchResult(
      exitCode: process.exitCode,
      stdout: process.stdout,
      stderr: process.stderr,
      timedOut: process.timedOut,
      tokensUsed: usage.tokens,
      sessionExternalId: usage.sessionId,
      resultText: usage.resultText ?? '',
      commandLine: commandLine,
    );
  }

  /// The invocation for display; args with spaces are quoted.
  static String _displayCommand(List<String> argv) =>
      argv.map((a) => a.contains(' ') ? '"$a"' : a).join(' ');

  /// Codex automation is non-interactive, so approval prompts would be
  /// cancelled instead of reaching a person. The adapter sets `-a never` while
  /// keeping Codex's own read-only/workspace-write sandbox. On Windows, remove
  /// ACL-protected Store alias directories from the child PATH: otherwise
  /// Codex discovers `pwsh.exe` there and every shell call fails with access
  /// denied instead of falling back to Windows PowerShell.
  static Map<String, String> processEnvironmentFor(
    String agent, [
    Map<String, String> provided = const {},
  ]) {
    final result = <String, String>{...provided};
    if (agent != 'codex' || !Platform.isWindows) return result;
    final inheritedPath = Platform.environment['PATH'] ?? '';
    final cleaned = inheritedPath
        .split(';')
        .where((part) => !part.toLowerCase().contains('windowsapps'))
        .toList();
    final preferred = <String>[
      if (Platform.environment['APPDATA'] case final appData?) '$appData\\npm',
      r'C:\Program Files\nodejs',
      r'C:\Windows\System32\WindowsPowerShell\v1.0',
    ];
    for (final directory in preferred.reversed) {
      if (!Directory(directory).existsSync()) continue;
      cleaned.removeWhere(
        (part) => part.toLowerCase() == directory.toLowerCase(),
      );
      cleaned.insert(0, directory);
    }
    result['PATH'] = cleaned.join(';');
    return result;
  }

  /// The display command WITHOUT launching — persisted when the step starts so
  /// the monitor shows what will run while the agent is still working.
  String previewCommand({
    required String agent,
    String? model,
    String? effort,
    required String workdir,
    String permissionsJson = '{}',
    String? resumeSessionId,
    String? newSessionId,
    String? codexSandbox,
  }) {
    final argv = _argv(
      agent: agent,
      model: _normalizeModel(agent, model),
      effort: _normalizeEffort(agent, effort),
      workdir: workdir,
      permissionsJson: permissionsJson,
      resumeSessionId: resumeSessionId,
      newSessionId: newSessionId,
      codexSandbox: codexSandbox,
    );
    return argv == null ? '' : '${_displayCommand(argv)}  (prompt via stdin)';
  }

  /// Users sometimes type a DISPLAY name ("Opus 4.8") into the model field; the
  /// CLIs want an alias ("opus"). Normalize the known families; pass anything
  /// else through trimmed (any id the CLI accepts is valid — the field is free).
  static String? _normalizeModel(String agent, String? model) {
    final m = model?.trim();
    if (m == null || m.isEmpty) return null;
    if (agent == 'claude-code' || agent == 'claude') {
      final low = m.toLowerCase();
      for (final alias in const ['opus', 'sonnet', 'haiku', 'fable']) {
        if (low == alias || low.startsWith('$alias ')) return alias;
      }
    }
    return m;
  }

  /// Reasoning-effort levels each CLI documents (July 2026):
  /// - claude: `--effort low|medium|high|xhigh|max` (claude --help);
  /// - codex: `model_reasoning_effort` minimal|low|medium|high|xhigh
  ///   (config reference; xhigh is model-dependent);
  /// - others: no effort flag — the value is DROPPED, never guessed.
  /// Cross-agent tolerance: a level one CLI lacks clamps to its nearest.
  static String? _normalizeEffort(String agent, String? effort) {
    final e = effort?.trim().toLowerCase();
    if (e == null || e.isEmpty) return null;
    switch (agent) {
      case 'claude-code':
      case 'claude':
        if (const ['low', 'medium', 'high', 'xhigh', 'max'].contains(e)) {
          return e;
        }
        return e == 'minimal' ? 'low' : null;
      case 'codex':
        if (const ['minimal', 'low', 'medium', 'high', 'xhigh'].contains(e)) {
          return e;
        }
        return e == 'max' ? 'xhigh' : null;
      default:
        return null;
    }
  }

  /// Best-effort extraction of token usage + the agent's own session id from the
  /// harness's structured output. Never throws — an unparseable shape yields
  /// (0, null), so token-budget enforcement and session linking degrade quietly.
  ({int tokens, String? sessionId, String? resultText}) parseStructuredOutput(
    String agent,
    String stdout,
  ) {
    final s = stdout.trim();
    if (s.isEmpty) return (tokens: 0, sessionId: null, resultText: null);
    var tokens = 0;
    String? sessionId;
    String? resultText;
    int fromUsage(Object? u) {
      if (u is! Map) return 0;
      final total = _int(u['total_tokens']);
      if (total > 0) return total;
      return _int(u['input_tokens']) +
          _int(u['output_tokens']) +
          _int(u['cache_read_input_tokens']) +
          _int(u['cache_creation_input_tokens']);
    }

    try {
      if (agent == 'claude-code' || agent == 'claude') {
        // claude -p --output-format json → a single JSON object.
        final j = jsonDecode(s);
        if (j is Map) {
          sessionId = j['session_id']?.toString();
          tokens = fromUsage(j['usage']);
          if (j['result'] is String) resultText = j['result'] as String;
        }
      } else {
        // codex/gemini stream JSONL → scan lines for usage + session/thread id
        // + the LAST agent message (the final answer).
        for (final line in const LineSplitter().convert(s)) {
          final t = line.trim();
          if (!t.startsWith('{')) continue;
          try {
            final j = jsonDecode(t);
            if (j is! Map) continue;
            sessionId ??=
                (j['session_id'] ??
                        j['thread_id'] ??
                        (j['thread'] is Map
                            ? (j['thread'] as Map)['id']
                            : null))
                    ?.toString();
            final u =
                j['usage'] ??
                (j['turn'] is Map ? (j['turn'] as Map)['usage'] : null);
            tokens += fromUsage(u);
            if (j['result'] is String) resultText = j['result'] as String;
            if (j['response'] is String) resultText = j['response'] as String;
            final item = j['item'];
            if (item is Map &&
                '${item['type'] ?? item['item_type'] ?? ''}'.contains(
                  'agent_message',
                ) &&
                item['text'] is String) {
              resultText = item['text'] as String;
            }
          } catch (_) {
            /* skip non-JSON line */
          }
        }
      }
    } catch (_) {
      /* unknown shape */
    }
    return (tokens: tokens, sessionId: sessionId, resultText: resultText);
  }

  static int _int(Object? v) => v is num ? v.toInt() : 0;

  /// Claude Code and Gemini can start a new conversation with an id chosen by
  /// the caller. Codex and Cursor allocate their own id, which is captured from
  /// structured output after the first turn.
  static bool canAssignSessionId(String agent) =>
      agent == 'claude-code' || agent == 'claude' || agent == 'gemini';

  /// The argv for a headless run of [agent] — the PROMPT IS NOT HERE (it goes
  /// via stdin). Flags are the documented non-interactive shapes for each CLI
  /// (2026).
  ///
  /// Claude Code deliberately does NOT use `--bare`: the step agent needs the
  /// project's `.mcp.json` (the Oracle MCP server) auto-discovered, or it cannot
  /// call `oracle_flow_step_context` / `oracle_flow_step_report`. Permissions:
  /// `acceptEdits` auto-approves file edits and the allowlist covers shell +
  /// every `oracle-ai` MCP tool, so a dev step can actually work headless.
  List<String>? _argv({
    required String agent,
    String? model,
    String? effort,
    required String workdir,
    String permissionsJson = '{}',
    String? resumeSessionId,
    String? newSessionId,
    String? codexSandbox,
  }) {
    final permissions = _permissions(permissionsJson);
    switch (agent) {
      case 'claude-code':
      case 'claude':
        // Project-scope MCP approval in ~/.claude.json is keyed by DIRECTORY.
        // A run's fresh worktree is a new, never-approved path, and headless
        // mode cannot show the trust prompt — the project's .mcp.json would be
        // silently skipped and the step could never call the Oracle tools.
        // Passing the file explicitly loads it without the trust gate.
        final mcpJson = File(
          '$workdir${Platform.pathSeparator}.mcp.json',
        );
        return [
          executableFor(agent),
          '-p',
          '--output-format',
          'json',
          if (mcpJson.existsSync()) ...['--mcp-config', mcpJson.path],
          '--permission-mode',
          permissions.workspaceWrite ? 'acceptEdits' : 'plan',
          '--allowedTools',
          [
            'Read',
            'Glob',
            'Grep',
            if (permissions.workspaceWrite) ...['Edit', 'Write'],
            if (permissions.shell) 'Bash',
            if (permissions.mcp) 'mcp__oracle-ai',
          ].join(','),
          if (model != null && model.isNotEmpty) ...['--model', model],
          if (effort != null) ...['--effort', effort],
          if (resumeSessionId != null) ...['--resume', resumeSessionId],
          if (resumeSessionId == null && newSessionId != null) ...[
            '--session-id',
            newSessionId,
          ],
        ];
      case 'codex':
        final sandboxMode = codexSandboxMode(
          workspaceWrite: permissions.workspaceWrite,
          override: codexSandbox,
        );
        // workspace-write only covers the CWD — but a git WORKTREE keeps its
        // real git dir under the MAIN repo's .git/worktrees/<name>, and the
        // Dart/Flutter toolchain writes lockfiles in the SDK / pub caches.
        // Without these extra roots, `git commit` and `flutter test` inside a
        // step die with "access denied" and the agent parks as blocked.
        final writableRoots = sandboxMode == 'workspace-write'
            ? codexWritableRoots(workdir)
            : const <String>[];
        return [
          executableFor(agent),
          // No interactive terminal exists in a flow worker. Never request an
          // approval that can only be cancelled; the sandbox below remains in
          // force and is derived from the node's permissions.
          '-a', 'never', 'exec',
          // Flow execution has no interactive user at the tool boundary. The
          // Oracle server is local, run-pinned and claim-token protected, so
          // approve its tools explicitly for this process. `required` also
          // makes Codex fail at startup instead of silently running without the
          // protocol server when the configuration is broken.
          '-c', 'mcp_servers.oracle-ai.required=true',
          '-c',
          'mcp_servers.oracle-ai.default_tools_approval_mode="approve"',
          '-c', 'mcp_servers.oracle-ai.tool_timeout_sec=300',
          '--json',
          '--sandbox',
          sandboxMode,
          if (writableRoots.isNotEmpty) ...[
            '-c',
            'sandbox_workspace_write.writable_roots='
                '${tomlStringArray(writableRoots)}',
          ],
          '-C', workdir,
          if (model != null && model.isNotEmpty) ...['-m', model],
          // Codex has no --effort flag; effort goes as a config override.
          if (effort != null) ...['-c', 'model_reasoning_effort=$effort'],
          if (resumeSessionId != null) ...['resume', resumeSessionId],
          '-', // read the next user turn from stdin
        ];
      case 'gemini':
        return [
          executableFor(agent), // non-TTY stdin = headless prompt
          '--approval-mode',
          permissions.shell ? 'yolo' : 'auto_edit',
          '--output-format', 'stream-json',
          if (model != null && model.isNotEmpty) ...['-m', model],
          if (resumeSessionId != null) ...['--resume', resumeSessionId],
          if (resumeSessionId == null && newSessionId != null) ...[
            '--session-id',
            newSessionId,
          ],
        ];
      case 'cursor':
        return [
          executableFor(agent),
          '-p',
          '--force',
          '--output-format',
          'stream-json',
          if (model != null && model.isNotEmpty) ...['--model', model],
          if (resumeSessionId != null) '--resume=$resumeSessionId',
        ];
      default:
        return null;
    }
  }

  /// The sandbox mode for a Codex step. On WINDOWS a WRITE step skips the OS
  /// sandbox (`danger-full-access`): the Windows sandbox is incompatible with
  /// what a write step must do — it applies DENY ACEs to `.git` dirs inside
  /// writable roots so `git commit` fails BY DESIGN (openai/codex#18918), its
  /// setup-refresh dies with error 5 on roots owned by Administrators
  /// (#31414/#29867/#24259) and leaves ACL debris on the machine
  /// (#27236/#31140/#15165). A write step already runs approvals-never inside
  /// its own worktree with the runner verifying outside — the exact trust
  /// level Claude/Gemini/Cursor steps have (none of them has an OS sandbox).
  /// On macOS/Linux the native sandbox (seatbelt/landlock) works and is kept,
  /// widened with [codexWritableRoots]. Read-only nodes keep `read-only`
  /// everywhere. [override] — the step config key `codexSandbox` — wins when
  /// it names a valid mode, so a flow author can force either behavior.
  static String codexSandboxMode({
    required bool workspaceWrite,
    String? override,
    bool? isWindows,
  }) {
    const valid = {'read-only', 'workspace-write', 'danger-full-access'};
    final o = override?.trim();
    if (o != null && valid.contains(o)) return o;
    if (!workspaceWrite) return 'read-only';
    return (isWindows ?? Platform.isWindows)
        ? 'danger-full-access'
        : 'workspace-write';
  }

  /// Extra writable roots for Codex's workspace-write sandbox, derived from
  /// the workdir (never configured by hand):
  /// 1. the MAIN repo's `.git` when [workdir] is a git worktree (its `.git`
  ///    FILE points at `<main>/.git/worktrees/<name>` — commits/index writes
  ///    land there, outside the cwd);
  /// 2. the Flutter SDK root (resolved once from PATH — `flutter test` takes a
  ///    lockfile in `<sdk>/bin/cache`);
  /// 3. the pub cache (`PUB_CACHE` / platform default).
  /// Best-effort: anything unresolvable is simply not added.
  static List<String> codexWritableRoots(String workdir) {
    final sep = Platform.pathSeparator;
    final roots = <String>[];
    void add(String? path) {
      final p = path?.trim();
      if (p == null || p.isEmpty || roots.contains(p)) return;
      roots.add(p);
    }

    try {
      final gitLink = File('$workdir$sep.git');
      if (gitLink.existsSync()) {
        final match = RegExp(
          r'gitdir:\s*(.+)',
        ).firstMatch(gitLink.readAsStringSync());
        if (match != null) {
          var gitdir = match.group(1)!.trim().replaceAll('/', sep);
          if (!_isAbsolutePath(gitdir)) gitdir = '$workdir$sep$gitdir';
          add(gitCommonDirOf(gitdir, sep));
        }
      }
    } catch (_) {
      /* not a worktree / unreadable — no extra root */
    }

    add(_flutterSdkRoot());

    final pubCache = Platform.environment['PUB_CACHE'];
    if (pubCache != null && pubCache.trim().isNotEmpty) {
      add(pubCache);
    } else if (Platform.isWindows) {
      final la = Platform.environment['LOCALAPPDATA'];
      if (la != null && Directory('$la\\Pub\\Cache').existsSync()) {
        add('$la\\Pub\\Cache');
      }
    } else {
      final home = Platform.environment['HOME'];
      if (home != null && Directory('$home/.pub-cache').existsSync()) {
        add('$home/.pub-cache');
      }
    }
    return roots;
  }

  /// `<main>/.git/worktrees/<name>` → `<main>/.git`; any other layout keeps
  /// the gitdir itself (still outside the cwd, still needs to be writable).
  static String gitCommonDirOf(String gitdir, String sep) {
    final segments = gitdir.split(sep);
    final wtIndex = segments.lastIndexOf('worktrees');
    if (wtIndex > 0 && segments[wtIndex - 1] == '.git') {
      return segments.sublist(0, wtIndex).join(sep);
    }
    return gitdir;
  }

  static bool _isAbsolutePath(String p) => Platform.isWindows
      ? RegExp(r'^([A-Za-z]:[\\/]|\\\\)').hasMatch(p)
      : p.startsWith('/');

  /// The Flutter SDK root, resolved from PATH once per process (probing runs
  /// `where`/`which`; a machine without Flutter simply gets no root).
  static String? _flutterSdkRoot() {
    if (_flutterProbed) return _flutterRootCache;
    _flutterProbed = true;
    try {
      final result = Process.runSync(
        Platform.isWindows ? 'where' : 'which',
        const ['flutter'],
        runInShell: true,
      );
      if (result.exitCode == 0) {
        final first = '${result.stdout}'
            .trim()
            .split('\n')
            .first
            .trim();
        if (first.isNotEmpty) {
          // <sdk>/bin/flutter(.bat) → <sdk>
          final root = File(first).parent.parent.path;
          if (Directory(root).existsSync()) _flutterRootCache = root;
        }
      }
    } catch (_) {
      /* no flutter on PATH */
    }
    return _flutterRootCache;
  }

  static String? _flutterRootCache;
  static bool _flutterProbed = false;

  /// A TOML inline array of strings for `-c key=[...]` overrides (backslashes
  /// escaped for Windows paths).
  static String tomlStringArray(List<String> values) {
    final items = values
        .map((v) => '"${v.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"')
        .join(',');
    return '[$items]';
  }

  static ({bool workspaceWrite, bool shell, bool mcp}) _permissions(
    String raw,
  ) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map && decoded.isNotEmpty) {
        return (
          workspaceWrite: '${decoded['workspace'] ?? 'write'}' != 'read',
          shell: decoded['shell'] != false,
          mcp: decoded['mcp'] != false,
        );
      }
    } catch (_) {
      // Save-time validation normally prevents this; preserve legacy defaults.
    }
    return (workspaceWrite: true, shell: true, mcp: true);
  }
}

class StepLauncherException implements Exception {
  final String message;
  StepLauncherException(this.message);
  @override
  String toString() => 'StepLauncherException: $message';
}
