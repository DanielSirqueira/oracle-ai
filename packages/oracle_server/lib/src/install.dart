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

## Start of every task
1. Resolve the project — call `oracle_project_resolve` with the absolute repo path (your cwd). Reuse the
   returned `projectId` for every other call this session.
2. Load the rules — call `oracle_rules_for_task` (projectId, optional scope). Treat `required` rules as
   mandatory and `recommended` as strong defaults.
3. Recall context — before exploring, `oracle_memory_search` and `oracle_architecture_get` / `_search`
   for what's relevant. If the request feels familiar, `oracle_request_search` finds past user demands
   like it; `oracle_request_messages` then shows how each was handled.
4. Pick up open work — `oracle_handoff_pending`, and `oracle_handoff_accept` the one you continue.

> Capture is automatic when hooks are installed — they record your session, each user request, and your
> work as `Session -> Request -> Messages`. You never log those by hand; just consolidate durable memories.

## While working
- Save a durable, non-obvious learning the moment you have one, with `oracle_memory_save`:
  - `tier`: `episodic` (this task) / `semantic` (lasting knowledge) / `procedural` (a how-to)
  - `kind`: `decision` / `gotcha` / `rule` / `fact`
  - `title`: a short, searchable headline; `body`: the fact AND why it matters
  - `importance`: 0..1 (higher = more central)
- Create or refine a rule with `oracle_rule_save` (`key`, `scope`, `title`, `content`,
  `severity` = required|recommended, `priority` 0..100). Re-saving the same `key` REFINES it (versioned).
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
