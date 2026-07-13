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
  final codexToml = "[mcp_servers.oracle-ai]\ncommand = '$command'\nargs = []";
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

String hooksJson({String host = '127.0.0.1', int port = 49500, String? token}) {
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
''';

void printInstallMcp({String? command}) {
  stdout.writeln('# Merge into .mcp.json (project root) — the Oracle AI MCP server.');
  if (command == null) {
    stdout.writeln('# Tip: pass the compiled binary path: install-mcp <path-to-oracle_ai>');
  }
  stdout.writeln(mcpJson(command: command));
}

void printInstallHooks({String host = '127.0.0.1', int port = 49500, String? token}) {
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
