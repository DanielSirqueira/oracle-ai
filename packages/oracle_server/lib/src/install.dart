import 'dart:convert';
import 'dart:io';

/// Generators for the client wiring (so an agent host like Claude Code can use
/// Oracle with no hand-written config). Printed to stdout for the user to merge.

String mcpJson({String? command}) {
  final entry = {
    'mcpServers': {
      'oracle-ai': {
        'type': 'stdio',
        'command': command ?? Platform.resolvedExecutable,
        'args': <String>[],
        // DB + embedding settings are read from the project's .env (loadEnv).
      },
    },
  };
  return const JsonEncoder.withIndent('  ').convert(entry);
}

/// Where each major agent keeps its MCP configuration file — so the user knows
/// exactly where to paste the `oracle-ai` server block above. Single source of
/// truth shared by the installer wizard and Oracle Studio.
///
/// [command] is the installed CLI path; it's only needed to render the one agent
/// whose format differs enough that the JSON block won't paste as-is (Codex uses
/// TOML). VS Code differs only by its top-level key (`servers`), noted below.
String agentTargetsMarkdown({required String command}) {
  // TOML *literal* string (single quotes) so Windows backslashes in the path are
  // taken verbatim instead of being read as escape sequences.
  final codexToml = _codexMcp(command);
  return '''
## Where to configure each agent

Most agents read the JSON block above (top-level `mcpServers`). Paste it into that
agent's MCP config file — typically one of these:

| Agent | Config file (Windows) | Scope |
| --- | --- | --- |
| Claude Code | `.mcp.json` in the project root — or run `claude mcp add` | project / user |
| Claude Desktop | `%APPDATA%\\Claude\\claude_desktop_config.json` | global |
| Cursor | `.cursor\\mcp.json` (project) · `%USERPROFILE%\\.cursor\\mcp.json` (global) | project / global |
| Windsurf | `%USERPROFILE%\\.codeium\\windsurf\\mcp_config.json` | global |
| Google Antigravity | `%USERPROFILE%\\.gemini\\config\\mcp_config.json` (global) · `.agents\\mcp_config.json` (workspace) | global / workspace |
| Gemini CLI | `%USERPROFILE%\\.gemini\\settings.json` · `.gemini\\settings.json` (project) | global / project |

On macOS/Linux replace `%USERPROFILE%` with `~`, and for Claude Desktop use
`~/Library/Application Support/Claude/` (macOS) or `~/.config/Claude/` (Linux).

**Two agents need a different shape:**

- **VS Code (GitHub Copilot)** — file `.vscode\\mcp.json`; the top-level key is
  `servers` (not `mcpServers`). Use the inner `"oracle-ai": { ... }` object under `servers`.
- **OpenAI Codex CLI** — file `%USERPROFILE%\\.codex\\config.toml`, which is TOML, not JSON:

```toml
$codexToml
```
''';
}

String hooksJson({String host = '127.0.0.1', int port = 47500, String? token}) {
  final url = 'http://$host:$port/hook';
  final trimmedToken = token?.trim() ?? '';
  final hasToken = trimmedToken.isNotEmpty;
  Map<String, Object> http({bool async = false, String? matcher}) => {
        if (matcher != null) 'matcher': matcher,
        'hooks': [
          {
            'type': 'http',
            'url': url,
            if (async) 'async': true,
            // When ORACLE_HOOK_TOKEN is set, the receiver requires this header.
            if (hasToken) 'headers': {'Authorization': 'Bearer $trimmedToken'},
          },
        ],
      };
  final entry = {
    'hooks': {
      'SessionStart': [http()], // sync — injects the session brief
      'UserPromptSubmit': [http()], // sync — injects per-prompt recall
      'Stop': [http(async: true)], // async capture
      'PostToolUse': [http(async: true, matcher: '*')],
      'PostCompact': [http(async: true)],
      'SessionEnd': [http(async: true)],
    },
  };
  return const JsonEncoder.withIndent('  ').convert(entry);
}

/// The detailed, host-agnostic instruction block a user drops into their
/// agent's memory file (Claude Code `CLAUDE.md`, Codex/opencode `AGENTS.md`) to
/// teach it the Oracle workflow: recall before re-deriving, record what's
/// durable, hand off what's open. Single source of truth — surfaced verbatim in
/// the installer's agent step and in Oracle Studio's Settings.
String agentProtocol() => r'''
# Oracle AI — long-term memory protocol

You have a persistent memory bank for this codebase, exposed as the `oracle_*` MCP tools.
Treat it as your long-term memory: recall before you re-derive, and record durable learnings as you go.
Prefer recalled facts over re-reading files; trust but verify — memory can be stale, so re-check before
acting on a claim that names a specific file, symbol, or value.

Scope hierarchy: **organization -> project -> module**. A project has many modules (a service, layer, or
package). Anchor knowledge at the RIGHT level and recall unions all three (most specific first). Never
register a submodule as its own project.

Call `oracle_*` through the MCP surface exposed by the client. Prefer a native direct tool when available.
Some Codex clients expose MCP tools only through `functions.exec` / `exec` as
`tools.mcp__oracle_ai__oracle_*`; in that client, use this supported programmatic wrapper and do not refuse
the task because a native direct tool is absent. Never emulate Oracle with shell, curl, or by launching its
executable yourself. In a flow step, always call `oracle_flow_step_context` first and
`oracle_flow_step_report` last, even when the result is partial or blocked.

## Start of every task
1. Resolve the project — call `oracle_project_resolve` with the absolute repo path (your cwd). Reuse the
   returned `projectId` for every other call this session.
2. Resolve the module — if you're working inside a subpackage/service/layer (a subpath of the repo root),
   call `oracle_module_resolve` (projectId + your cwd) to get a `moduleId`. Reuse it so module-specific
   knowledge scopes to the module — NOT the whole project, and NEVER a separate fake project. At the repo
   root, there's no module (the work is project-level) — skip this.
3. Load the rules — call `oracle_rules_for_task` (projectId, plus `moduleId` when set, optional scope).
   Module rules override project rules override organization rules. Treat `required` as mandatory,
   `recommended` as strong defaults.
4. Recall context — before exploring, `oracle_memory_search` and `oracle_architecture_search` (pass
   `projectId` AND `moduleId` when you have one — recall returns module + project + organization knowledge,
   most specific ranked first). If the request feels familiar, `oracle_request_search` finds past user
   demands like it; `oracle_request_messages` shows how each was handled.
5. Pick up open work — `oracle_handoff_pending`, and `oracle_handoff_accept` the one you continue.

> Capture is automatic when hooks are installed — they record your session, each user request, and your
> work as `Session -> Request -> Messages`. You never log those by hand; just consolidate durable memories.

## While working
- Scope every save to the right level: pass `moduleId` for knowledge specific to the module you're in,
  `projectId` for project-wide knowledge, or `organizationId` for something true across the whole
  organization. Most saves are module- or project-level. This applies to memories, rules, architecture
  and skills alike.
- Save a durable, non-obvious learning the moment you have one, with `oracle_memory_save`:
  - `tier`: `episodic` (this task) / `semantic` (lasting knowledge) / `procedural` (a how-to)
  - `kind`: `decision` / `gotcha` / `rule` / `fact`
  - `title`: a short, searchable headline; `body`: the fact AND why it matters
  - `importance`: 0..1 (higher = more central)
- Create or refine a rule with `oracle_rule_save` (`key`, `scope`, `title`, `content`,
  `severity` = required|recommended, `priority` 0..100 — LOWER = more relevant, 1 first). Re-saving the same `key` REFINES it (versioned).
- Keep architecture current per area with `oracle_architecture_save`.

## What to save — and what not to
- DO save: decisions + their rationale, gotchas/footguns, conventions, hard-won facts, cross-cutting context.
- DON'T save: anything derivable from the code or git history, transient chatter, secrets, or one-off
  trivia. Bad memory is worse than no memory.
- Fix bad memory: re-save to supersede it, `oracle_memory_forget` it, or `oracle_rule_retire` a dead rule.

## End of a task / before the context window fills up
- Persist the key learnings (above), then write a handoff with `oracle_handoff_begin`
  (`summary`, `openQuestions`, `nextSteps`, `filesTouched`) so the next session continues without
  re-explaining.

## Specs & reviews (RFCs)
Before implementing a non-trivial spec — or when asked to review one — use the RFC flow: a structured,
evidence-grounded review that hardens a spec before any code is written.
- Author: publish the spec as a SECTIONED RFC with `oracle_rfc_open` (mark the sections your rfc_type
  requires + their coverage). It opens for review.
- Review: find open RFCs with `oracle_rfc_list_open`; read one with `oracle_rfc_get` — it returns the RFC
  PLUS a `grounding` block (project rules + prior decisions, each with an id). Post STRUCTURED findings with
  `oracle_rfc_comment` (a gap/inconsistency/bug/blocker MUST carry a proposedSolution). GROUND every finding
  with `oracle_rfc_evidence_add`, citing a real rule/memory/architecture id (from the grounding block) or a
  file+excerpt — an unverified finding does NOT gate completion, so never post hallucinated blockers.
- Contest / settle: `oracle_rfc_relate` (supports|refutes|…), `oracle_rfc_resolve` (accept/reject a finding).
- Consolidate: `oracle_rfc_revise` publishes a new version; `oracle_rfc_round_start`/`oracle_rfc_round_close`
  bracket a round. Record decisions with `oracle_rfc_decide` (`humanApproved` is the gate for product calls).
- Finalize: `oracle_rfc_status` shows readiness; `oracle_rfc_finalize` approves ONLY when no verified critical
  is open and every required section is covered, and writes the decisions back to memory.

## Tool cheat-sheet (intent -> tool)
- Map cwd -> a stable projectId ............ `oracle_project_resolve`
- Map a subpath -> a moduleId .............. `oracle_module_resolve` (list: `oracle_module_list`)
- Get the rules that apply to the task ..... `oracle_rules_for_task`
- Recall a past fact / decision / gotcha ... `oracle_memory_search`
- Find a past user demand like this one .... `oracle_request_search` -> `oracle_request_messages`
- Read or search the architecture .......... `oracle_architecture_get` / `oracle_architecture_search`
- Save a durable learning .................. `oracle_memory_save`
- Create or refine a development rule ...... `oracle_rule_save`
- Re-rank a rule without a new version ..... `oracle_rule_set_priority`
- Hand off open work to the next session ... `oracle_handoff_begin`
- Pick up the previous session's handoff ... `oracle_handoff_pending` / `oracle_handoff_accept`
- Forget wrong / obsolete memory ........... `oracle_memory_forget`
- Publish a spec for multi-agent review .... `oracle_rfc_open`
- Discover / read an open RFC .............. `oracle_rfc_list_open` / `oracle_rfc_get`
- Post a grounded review finding .......... `oracle_rfc_comment` + `oracle_rfc_evidence_add`
- Consolidate / finalize an RFC ........... `oracle_rfc_revise` / `oracle_rfc_finalize`
''';

// ─────────────────────────────────────────────────────────────────────────────
// Per-agent integration matrix
//
// Every supported agent wired to Oracle from ONE source of truth: where its MCP
// config lives, the exact snippet, whether/how it can drive the capture hooks,
// and which instruction file carries the protocol. Both the installer wizard and
// Oracle Studio render their per-agent tabs from `agentIntegrations()`.
// ─────────────────────────────────────────────────────────────────────────────

/// How an agent can reach Oracle's hook receiver for automatic capture/injection.
enum HookSupport {
  /// Native HTTP hooks — the agent POSTs straight to the receiver (Claude Code).
  http,

  /// Command-only hooks — the agent runs our `forward-hook` bridge, which relays
  /// the event JSON to the receiver (Codex, Cursor, Gemini CLI, VS Code Copilot).
  bridge,

  /// No lifecycle hooks — recall/capture is manual through the MCP tools + the
  /// protocol in the instruction file (Windsurf, Antigravity).
  none,
}

/// One agent's complete wiring. Text is language-neutral (paths + config); the
/// UIs wrap it with localized section labels.
class AgentIntegration {
  /// Stable slug — also the `forward-hook --agent <id>` capture tag.
  final String id;
  final String name;

  /// Where the MCP server config file lives (Windows path; note macOS/Linux in UI).
  final String mcpFile;

  /// The exact block to paste into [mcpFile].
  final String mcpSnippet;

  /// Optional one-line CLI that writes the MCP config for you (null if none).
  final String? mcpCli;

  final HookSupport hooks;

  /// Where the hooks config lives (null when [hooks] is [HookSupport.none]).
  final String? hooksFile;

  /// The exact hooks block to paste into [hooksFile] (null when unsupported).
  final String? hooksSnippet;

  /// The instruction file that should carry [agentProtocol] for this agent.
  final String instructionFile;

  const AgentIntegration({
    required this.id,
    required this.name,
    required this.mcpFile,
    required this.mcpSnippet,
    this.mcpCli,
    required this.hooks,
    this.hooksFile,
    this.hooksSnippet,
    required this.instructionFile,
  });
}

const _enc = JsonEncoder.withIndent('  ');

/// The shell command an agent's command-hook runs to relay one event: the quoted
/// CLI path + `forward-hook`, tagged with the agent id so capture attributes the
/// session. Quoting matters — the installed path contains a space ("Oracle AI").
String _bridgeCommand(String command, String id) => '"$command" forward-hook --agent $id';

Map<String, Object> _cmdHook(String bridge, {String? matcher}) => {
      if (matcher != null) 'matcher': matcher,
      'hooks': [
        {'type': 'command', 'command': bridge},
      ],
    };

/// Claude-shaped command hooks (Codex `~/.codex/hooks.json`, VS Code
/// `.claude/settings.json`): a `hooks` map keyed by PascalCase events.
String _claudeShapeCommandHooks(String bridge, List<String> events) => _enc.convert({
      'hooks': {
        for (final e in events) e: [_cmdHook(bridge, matcher: e == 'PostToolUse' ? '*' : null)],
      },
    });

/// Cursor `.cursor/hooks.json`: `{version, hooks:{<camelCaseEvent>:[{command,type}]}}`.
String _cursorHooks(String bridge) {
  List<Map<String, String>> e() => [
        {'command': bridge, 'type': 'command'},
      ];
  return _enc.convert({
    'version': 1,
    'hooks': {
      'sessionStart': e(),
      'beforeSubmitPrompt': e(),
      'afterFileEdit': e(),
      'afterShellExecution': e(),
      'afterMCPExecution': e(),
      'stop': e(),
    },
  });
}

/// Gemini CLI hooks (same `~/.gemini/settings.json`, under `hooks`): Gemini names
/// tool events `AfterTool` and has no prompt-submit event.
String _geminiHooks(String bridge) => _enc.convert({
      'hooks': {
        'SessionStart': [_cmdHook(bridge)],
        'AfterTool': [_cmdHook(bridge, matcher: '*')],
        'SessionEnd': [_cmdHook(bridge)],
      },
    });

/// Antigravity `~/.gemini/config/hooks.json`: top-level NAMED groups (not a
/// `hooks` key), each event → `[{matcher, hooks:[{type,command,timeout}]}]`.
/// Its events are PascalCase but distinct (no SessionStart/UserPromptSubmit); the
/// payload carries no event name, so each command passes `--event` explicitly.
/// Capture-only here: PostToolUse + Stop (Antigravity's payload has no inline
/// prompt/response — those live in a separate transcript file).
String _antigravityHooks(String command) {
  String cmd(String ev) => '"$command" forward-hook --agent antigravity --event $ev';
  Map<String, Object> entry(String ev, {String? matcher}) => {
        if (matcher != null) 'matcher': matcher,
        'hooks': [
          {'type': 'command', 'command': cmd(ev), 'timeout': 30},
        ],
      };
  return _enc.convert({
    'oracle-ai': {
      'PostToolUse': [entry('PostToolUse', matcher: '*')],
      'Stop': [entry('Stop')],
    },
  });
}

/// VS Code Copilot MCP config uses the top-level `servers` key (not `mcpServers`).
String _vscodeMcp(String command) => _enc.convert({
      'servers': {
        'oracle-ai': {'type': 'stdio', 'command': command, 'args': <String>[]},
      },
    });

/// Codex MCP config is TOML. Literal (single-quoted) string keeps Windows
/// backslashes verbatim. `network_access` is part of the contract: the
/// workspace-write sandbox blocks network by default — including for MCP
/// servers spawned by the ChatGPT/Codex desktop app — and oracle-ai needs to
/// reach the local PostgreSQL.
String _codexMcp(String command) => '''[mcp_servers.oracle-ai]
command = '$command'
args = []
required = true
startup_timeout_sec = 30
tool_timeout_sec = 300
default_tools_approval_mode = "approve"

[sandbox_workspace_write]
network_access = true''';

/// The full per-agent matrix. [command] is the installed CLI path; [host]/[port]/
/// [token] describe the running hook receiver (from the installed `.env`).
List<AgentIntegration> agentIntegrations({
  required String command,
  String host = '127.0.0.1',
  int port = 47500,
  String? token,
}) {
  final mcpStd = mcpJson(command: command); // standard {mcpServers:{oracle-ai:{…}}}
  String bridge(String id) => _bridgeCommand(command, id);
  return [
    AgentIntegration(
      id: 'claude-code',
      name: 'Claude Code',
      mcpFile: r'.mcp.json (project root) · ~/.claude.json (global)',
      mcpSnippet: mcpStd,
      mcpCli: 'claude mcp add oracle-ai -- "$command"',
      hooks: HookSupport.http,
      hooksFile: r'~/.claude/settings.json ("hooks" block)',
      hooksSnippet: hooksJson(host: host, port: port, token: token),
      instructionFile: 'CLAUDE.md',
    ),
    AgentIntegration(
      id: 'codex',
      name: 'Codex CLI',
      mcpFile: r'~/.codex/config.toml ([mcp_servers.oracle-ai] block)',
      mcpSnippet: _codexMcp(command),
      mcpCli: 'codex mcp add oracle-ai -- "$command"',
      hooks: HookSupport.bridge,
      hooksFile: r'~/.codex/hooks.json',
      // Codex has no SessionEnd event; Stop covers turn end. PostCompact mirrors
      // Claude's config so compaction summaries are captured too.
      hooksSnippet: _claudeShapeCommandHooks(
          bridge('codex'), const ['SessionStart', 'UserPromptSubmit', 'PostToolUse', 'PostCompact', 'Stop']),
      instructionFile: 'AGENTS.md',
    ),
    AgentIntegration(
      id: 'cursor',
      name: 'Cursor',
      mcpFile: r'.cursor/mcp.json (project) · ~/.cursor/mcp.json (global)',
      mcpSnippet: mcpStd,
      hooks: HookSupport.bridge,
      hooksFile: r'.cursor/hooks.json (project) · ~/.cursor/hooks.json (global)',
      hooksSnippet: _cursorHooks(bridge('cursor')),
      instructionFile: 'AGENTS.md',
    ),
    AgentIntegration(
      id: 'gemini',
      name: 'Gemini CLI',
      mcpFile: r'~/.gemini/settings.json (project: .gemini/settings.json)',
      mcpSnippet: mcpStd,
      hooks: HookSupport.bridge,
      hooksFile: r'~/.gemini/settings.json (same file, "hooks" block)',
      hooksSnippet: _geminiHooks(bridge('gemini')),
      instructionFile: 'GEMINI.md',
    ),
    AgentIntegration(
      id: 'vscode',
      name: 'VS Code (Copilot)',
      mcpFile: r'.vscode/mcp.json (top-level key: "servers")',
      mcpSnippet: _vscodeMcp(command),
      hooks: HookSupport.bridge,
      hooksFile: r'.claude/settings.json (Copilot reads Claude format)',
      hooksSnippet: _claudeShapeCommandHooks(
          bridge('vscode'), const ['SessionStart', 'UserPromptSubmit', 'PostToolUse', 'Stop']),
      instructionFile: '.github/copilot-instructions.md',
    ),
    AgentIntegration(
      id: 'windsurf',
      name: 'Windsurf',
      mcpFile: r'~/.codeium/windsurf/mcp_config.json (global)',
      mcpSnippet: mcpStd,
      hooks: HookSupport.none,
      instructionFile: 'AGENTS.md',
    ),
    AgentIntegration(
      id: 'antigravity',
      name: 'Antigravity',
      mcpFile: r'~/.gemini/config/mcp_config.json',
      mcpSnippet: mcpStd,
      hooks: HookSupport.bridge,
      hooksFile: r'~/.gemini/config/hooks.json',
      hooksSnippet: _antigravityHooks(command),
      instructionFile: 'AGENTS.md',
    ),
  ];
}

void printInstallMcp({String? command}) {
  stdout.writeln('# Merge into .mcp.json (project root) — the Oracle AI MCP server.');
  if (command == null) {
    stdout.writeln('# Tip: pass the compiled binary path: install-mcp <path-to-oracle_ai>');
  }
  stdout.writeln(mcpJson(command: command));
}

void printInstallHooks({String host = '127.0.0.1', int port = 47500, String? token}) {
  stdout
    ..writeln('# Merge the "hooks" block into your Claude Code settings.json.')
    ..writeln('# SessionStart + UserPromptSubmit are SYNCHRONOUS (they inject recalled')
    ..writeln('# context); the capture hooks are async so they never block the agent.')
    ..writeln('# The Oracle server must be running its hook receiver on this port.');
  if (token != null && token.trim().isNotEmpty) {
    stdout.writeln('# ORACLE_HOOK_TOKEN is set — the Authorization header below is required.');
  }
  stdout.writeln(hooksJson(host: host, port: port, token: token));
}
