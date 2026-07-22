import 'dart:io';

import 'package:oracle_server/src/flow_runner/step_launcher.dart';
import 'package:test/test.dart';

void main() {
  final launcher = StepLauncher();
  String cmd(
    String agent, {
    String? model,
    String? effort,
    String permissions = '{}',
    String? resumeSessionId,
    String? newSessionId,
  }) => launcher.previewCommand(
    agent: agent,
    model: model,
    effort: effort,
    workdir: 'D:/repo',
    permissionsJson: permissions,
    resumeSessionId: resumeSessionId,
    newSessionId: newSessionId,
  );

  group('claude-code', () {
    test('display name normalizes to the CLI alias', () {
      expect(cmd('claude-code', model: 'Opus 4.8'), contains('--model opus'));
    });

    test('effort becomes --effort (documented levels pass through)', () {
      for (final e in ['low', 'medium', 'high', 'xhigh', 'max']) {
        expect(cmd('claude-code', effort: e), contains('--effort $e'));
      }
    });

    test("codex-only 'minimal' clamps to low; empty adds no flag", () {
      expect(cmd('claude-code', effort: 'minimal'), contains('--effort low'));
      expect(cmd('claude-code'), isNot(contains('--effort')));
    });

    test('worktree .mcp.json is loaded explicitly (trust is per-directory)', () async {
      final dir = await Directory.systemTemp.createTemp('oracle_mcpjson_');
      addTearDown(() => dir.delete(recursive: true));
      final without = launcher.previewCommand(
        agent: 'claude-code',
        workdir: dir.path,
      );
      expect(without, isNot(contains('--mcp-config')));
      File(
        '${dir.path}${Platform.pathSeparator}.mcp.json',
      ).writeAsStringSync('{"mcpServers":{"oracle-ai":{}}}');
      final with_ = launcher.previewCommand(
        agent: 'claude-code',
        workdir: dir.path,
      );
      expect(with_, contains('--mcp-config'));
      expect(with_, contains('.mcp.json'));
    });

    test('starts a named session and resumes that exact conversation', () {
      expect(
        cmd(
          'claude-code',
          newSessionId: '11111111-1111-4111-8111-111111111111',
        ),
        contains('--session-id 11111111-1111-4111-8111-111111111111'),
      );
      expect(
        cmd('claude-code', resumeSessionId: 'claude-session'),
        contains('--resume claude-session'),
      );
    });
  });

  group('codex', () {
    test('model id passes through with -m', () {
      expect(cmd('codex', model: 'gpt-5.5'), contains('-m gpt-5.5'));
      expect(cmd('codex'), contains('--json'));
    });

    test('runs non-interactively with a platform-derived sandbox mode', () {
      final command = cmd('codex');
      expect(command, contains('-a never exec'));
      expect(command, contains('mcp_servers.oracle-ai.required=true'));
      expect(
        command,
        contains('mcp_servers.oracle-ai.default_tools_approval_mode="approve"'),
      );
      // Windows write steps skip the broken OS sandbox; elsewhere it is kept.
      expect(
        command,
        contains(
          Platform.isWindows
              ? '--sandbox danger-full-access'
              : '--sandbox workspace-write',
        ),
      );
    });

    test('sandbox mode decision: platform default and per-step override', () {
      // Write steps: Windows opts out of the broken OS sandbox; POSIX keeps it.
      expect(
        StepLauncher.codexSandboxMode(workspaceWrite: true, isWindows: true),
        'danger-full-access',
      );
      expect(
        StepLauncher.codexSandboxMode(workspaceWrite: true, isWindows: false),
        'workspace-write',
      );
      // Read-only nodes never widen, on any platform.
      expect(
        StepLauncher.codexSandboxMode(workspaceWrite: false, isWindows: true),
        'read-only',
      );
      // A valid step-config override always wins; junk is ignored.
      expect(
        StepLauncher.codexSandboxMode(
          workspaceWrite: true,
          isWindows: true,
          override: 'workspace-write',
        ),
        'workspace-write',
      );
      expect(
        StepLauncher.codexSandboxMode(
          workspaceWrite: true,
          isWindows: false,
          override: 'danger-full-access',
        ),
        'danger-full-access',
      );
      expect(
        StepLauncher.codexSandboxMode(
          workspaceWrite: true,
          isWindows: true,
          override: 'yolo',
        ),
        'danger-full-access',
      );
    });

    test('effort becomes the model_reasoning_effort config override', () {
      for (final e in ['minimal', 'low', 'medium', 'high', 'xhigh']) {
        expect(
          cmd('codex', effort: e),
          contains('-c model_reasoning_effort=$e'),
        );
      }
    });

    test("claude-only 'max' clamps to xhigh", () {
      expect(
        cmd('codex', effort: 'max'),
        contains('-c model_reasoning_effort=xhigh'),
      );
    });

    test('worktree gitdir resolves to the main repo .git writable root', () {
      const sep = '\\';
      expect(
        StepLauncher.gitCommonDirOf(
          r'D:\rp\rp-system\.git\worktrees\erro-123',
          sep,
        ),
        r'D:\rp\rp-system\.git',
      );
      // A non-worktree layout keeps the gitdir itself.
      expect(
        StepLauncher.gitCommonDirOf(r'D:\elsewhere\gitdir', sep),
        r'D:\elsewhere\gitdir',
      );
    });

    test('TOML array escapes Windows backslashes for -c overrides', () {
      expect(
        StepLauncher.tomlStringArray([r'D:\rp\x\.git', '/tmp/pub']),
        r'["D:\\rp\\x\\.git","/tmp/pub"]',
      );
    });

    test('a git worktree workdir gets extra writable roots in the argv', () async {
      final main = await Directory.systemTemp.createTemp('oracle_main_');
      final wt = await Directory.systemTemp.createTemp('oracle_wt_');
      addTearDown(() => main.delete(recursive: true));
      addTearDown(() => wt.delete(recursive: true));
      final gitdir = Directory(
        '${main.path}${Platform.pathSeparator}.git'
        '${Platform.pathSeparator}worktrees${Platform.pathSeparator}x',
      )..createSync(recursive: true);
      File('${wt.path}${Platform.pathSeparator}.git').writeAsStringSync(
        'gitdir: ${gitdir.path.replaceAll(Platform.pathSeparator, '/')}\n',
      );
      // Forced workspace-write (the POSIX default) derives the extra roots.
      final command = launcher.previewCommand(
        agent: 'codex',
        workdir: wt.path,
        codexSandbox: 'workspace-write',
      );
      expect(command, contains('sandbox_workspace_write.writable_roots='));
      expect(
        command,
        contains(
          '${main.path}${Platform.pathSeparator}.git'.replaceAll(r'\', r'\\'),
        ),
      );
      // Full access needs no roots; read-only must NOT widen the sandbox.
      final full = launcher.previewCommand(
        agent: 'codex',
        workdir: wt.path,
        codexSandbox: 'danger-full-access',
      );
      expect(full, isNot(contains('writable_roots')));
      final readOnly = launcher.previewCommand(
        agent: 'codex',
        workdir: wt.path,
        permissionsJson: '{"workspace":"read"}',
      );
      expect(readOnly, isNot(contains('writable_roots')));
      expect(readOnly, contains('--sandbox read-only'));
    });

    test('resume subcommand keeps global flags before the thread id', () {
      final command = cmd('codex', resumeSessionId: 'codex-thread');
      expect(command, contains('-a never exec'));
      expect(command.indexOf('exec'), lessThan(command.indexOf('--json')));
      expect(command, contains('resume codex-thread -'));
      expect(command.indexOf('--json'), lessThan(command.indexOf('resume')));
    });
  });

  test(
    'gemini/cursor: model passes through, effort is dropped (no CLI flag)',
    () {
      expect(
        cmd('gemini', model: 'gemini-3-pro-preview', effort: 'high'),
        contains('-m gemini-3-pro-preview'),
      );
      expect(cmd('gemini', effort: 'high'), isNot(contains('effort')));
      expect(cmd('gemini'), contains('--output-format stream-json'));
      expect(
        cmd('cursor', model: 'sonnet-4.5', effort: 'high'),
        contains('--model sonnet-4.5'),
      );
      expect(cmd('cursor', effort: 'high'), isNot(contains('effort')));
      expect(cmd('cursor'), contains('--output-format stream-json'));
    },
  );

  test('gemini and cursor use their supported session continuation flags', () {
    expect(
      cmd('gemini', newSessionId: 'gemini-session'),
      contains('--session-id gemini-session'),
    );
    expect(
      cmd('gemini', resumeSessionId: 'gemini-session'),
      contains('--resume gemini-session'),
    );
    expect(
      cmd('cursor', resumeSessionId: 'cursor-chat'),
      contains('--resume=cursor-chat'),
    );
  });

  test('only CLIs with a session creation flag accept assigned ids', () {
    expect(StepLauncher.canAssignSessionId('claude-code'), isTrue);
    expect(StepLauncher.canAssignSessionId('gemini'), isTrue);
    expect(StepLauncher.canAssignSessionId('codex'), isFalse);
    expect(StepLauncher.canAssignSessionId('cursor'), isFalse);
  });

  test(
    'resolved Codex executable is actually callable when installed',
    () async {
      final executable = StepLauncher.executableFor('codex');
      if (!Platform.isWindows) return;
      expect(executable, 'codex');
      final result = await Process.run(
        executable,
        const ['--version'],
        runInShell: true,
        environment: StepLauncher.processEnvironmentFor('codex'),
      );
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect('${result.stdout}', contains('codex'));
    },
  );

  group('structured session id capture', () {
    test('Claude JSON exposes its resumable session and usage', () {
      final parsed = launcher.parseStructuredOutput(
        'claude-code',
        '{"session_id":"claude-123","result":"done",'
            '"usage":{"input_tokens":10,"output_tokens":5}}',
      );
      expect(parsed.sessionId, 'claude-123');
      expect(parsed.tokens, 15);
      expect(parsed.resultText, 'done');
    });

    test('Codex JSONL captures thread.started and final agent message', () {
      final parsed = launcher.parseStructuredOutput(
        'codex',
        '{"type":"thread.started","thread_id":"codex-456"}\n'
            '{"type":"item.completed","item":{"type":"agent_message","text":"fixed"}}\n'
            '{"type":"turn.completed","usage":{"input_tokens":20,"output_tokens":8}}',
      );
      expect(parsed.sessionId, 'codex-456');
      expect(parsed.tokens, 28);
      expect(parsed.resultText, 'fixed');
    });

    test('Gemini and Cursor stream events expose session_id', () {
      expect(
        launcher
            .parseStructuredOutput(
              'gemini',
              '{"type":"init","session_id":"gemini-789"}',
            )
            .sessionId,
        'gemini-789',
      );
      expect(
        launcher
            .parseStructuredOutput(
              'cursor',
              '{"type":"system","subtype":"init","session_id":"cursor-abc"}\n'
                  '{"type":"result","result":"finished","session_id":"cursor-abc"}',
            )
            .sessionId,
        'cursor-abc',
      );
      expect(
        launcher
            .parseStructuredOutput(
              'cursor',
              '{"type":"result","result":"finished","session_id":"cursor-abc"}',
            )
            .resultText,
        'finished',
      );
    });
  });

  test('read-only permissions are translated per adapter', () {
    const readOnly = '{"workspace":"read","shell":false,"mcp":true}';
    expect(
      cmd('codex', permissions: readOnly),
      contains('--sandbox read-only'),
    );
    expect(
      cmd('claude-code', permissions: readOnly),
      contains('--permission-mode plan'),
    );
    expect(cmd('claude-code', permissions: readOnly), isNot(contains('Bash')));
    expect(
      cmd('gemini', permissions: readOnly),
      contains('--approval-mode auto_edit'),
    );
  });

  test('unknown agent yields an empty preview (no adapter)', () {
    expect(cmd('copilot'), isEmpty);
  });
}
