# Agent integration

## CLI contract for flow execution

The Flow Runner invokes each supported agent through its public CLI command:
`claude`, `codex`, `gemini`, or `cursor-agent`. A hidden executable inside an
application/package is not treated as the integration contract. Preflight runs
the command's lightweight version check and blocks the run with a visible error
when the CLI is not callable.

Codex flow steps are non-interactive. The runner therefore uses approval policy
`never` so an MCP call is returned to the model instead of being silently
cancelled while no terminal is attached. The node's configured Codex sandbox
(`read-only` or `workspace-write`) remains enabled; the runner does not use the
dangerous sandbox-bypass option. On Windows, the child PATH prioritizes the
global npm CLI and Node.js and excludes inaccessible Microsoft Store aliases.

## Flow-step protocol failures (troubleshooting)

The runner fails a step with `PROTOCOLO NÃO CUMPRIDO: você não chamou
oracle_flow_step_report` whenever the step ends without a stored report. A real
Codex run (2026-07-22) showed this error has **three distinct root causes**,
each with its own fix:

### 1. Claim token never reaches the MCP server (Codex — was systematic)

`oracle_flow_step_report` validates a per-attempt `claimToken`. The server used
to fall back to the `ORACLE_RUN_STEP_TOKEN` environment variable — which works
for hosts that spawn the Oracle MCP server as a child of the launched CLI with
an inherited environment (Claude Code), but **not for Codex**: its app runtime
spawns/holds the MCP server without the worker's environment, so the fallback
is always empty and every report was rejected with *"Invalid or stale step
claim token — Does not own this attempt"* — even though the agent did call the
tool. The runner then counted the attempt as a protocol failure.

Fixed at three layers (no configuration needed, works for every agent):
- the step **prompt** now inlines `claimToken: "<value>"` literally into the
  protocol's step 5, with a warning that the report is rejected without it;
- `oracle_flow_step_context` now returns `runStep.claimToken`, so a resumed
  session that lost its prompt can recover it;
- the rejection message now says where to get the token.

### 2. Transient host cancellations: "user cancelled MCP tool call" (Codex)

Codex clients that expose MCP tools through the `exec`/`node_repl` wrapper
(`tools.mcp__oracle_ai__oracle_*`) intermittently cancel the nested MCP call
before it reaches Oracle — the same call typically succeeds when repeated
seconds later. With `-a never` the cancellation is instant and looks like a
user decision, so agents used to give up (or report "blocked" — which was also
cancelled). The prompt and the MCP `instructions` now teach: **retry the same
call up to 3 times** before treating it as a blocker. The runner additionally
parks the run (instead of burning retries) when the final answer shows a
connector cancellation.

### 3. Windows sandbox cannot execute the Store `pwsh.exe` (Codex on Windows)

Codex's Windows sandbox spawns shell commands via `CreateProcessAsUserW` with a
restricted token. When `pwsh.exe` resolves to the Microsoft Store alias under
`%LOCALAPPDATA%\Microsoft\WindowsApps`, the directory's ACL denies that token
and **every shell command inside the step** fails with
`CreateProcessAsUserW failed: 5 (Acesso negado)` — while MCP keeps working,
which hides the cause. Cleaning the child PATH does not help because the Codex
app runtime resolves the alias from the login environment. Machine-level fix
(one of):
- install PowerShell 7 outside the Store — `winget install --id
  Microsoft.PowerShell --scope machine` (the MSI lands in the system PATH,
  which wins over the user's WindowsApps entry); or
- disable the `pwsh.exe` alias in Windows Settings → Apps → App execution
  aliases.

The agent doctor (Studio → flow editor → agent diagnostics) now detects the
Store-only `pwsh` and shows this fix; the flow still runs with the warning, but
shell-dependent steps will fail until it is resolved.

### 4. The Windows sandbox cannot run a write step at all (Codex)

Two successive failures showed the Codex **Windows** sandbox is incompatible
with what a write step must do:

1. `workspace-write` only allows writes under the CWD, but a git worktree's
   real git dir lives under the MAIN repo (`<main>/.git/worktrees/<name>`)
   and the Dart/Flutter toolchain takes lockfiles in the SDK and pub caches —
   `git commit` and `flutter test` die with "access denied".
2. Widening the sandbox with `sandbox_workspace_write.writable_roots` made it
   WORSE: the sandbox setup then fails outright with
   `helper_unknown_error: setup refresh had errors` before ANY process runs.
   Upstream issues confirm this is structural, not environmental:
   - [#18918](https://github.com/openai/codex/issues/18918) — the sandbox
     applies **DENY ACEs to `.git` dirs inside writable roots**: commits fail
     by design;
   - [#31414](https://github.com/openai/codex/issues/31414) /
     [#29867](https://github.com/openai/codex/issues/29867) /
     [#24259](https://github.com/openai/codex/issues/24259) — setup refresh
     dies with error 5 on roots owned by `BUILTIN\Administrators` (the usual
     owner of `.git` on many repos) and on prior ACL debris;
   - [#15165](https://github.com/openai/codex/issues/15165) /
     [#27236](https://github.com/openai/codex/issues/27236) /
     [#31140](https://github.com/openai/codex/issues/31140) — grants don't
     propagate to existing files and the leftover ACEs (orphan sandbox-user
     SIDs, `CodexSandboxUsers` grants) break later runs and even unrelated
     apps.

Resolution (the launcher's `codexSandboxMode`): on **Windows a write step runs
`--sandbox danger-full-access`** — the same trust level every other agent step
already has (Claude/Gemini/Cursor have no OS sandbox; the real containment is
the isolated worktree, approvals `never`, and the runner verifying outside the
agent). It also sidesteps the Store-pwsh spawn failure and produces zero ACL
residue. On macOS/Linux the native sandbox works and is kept
(`workspace-write` + auto-derived `writable_roots`: main `.git` from the
worktree's `gitdir:` pointer, Flutter SDK root, pub cache). Read-only nodes
keep `--sandbox read-only` on every platform. A flow author can force any mode
per step with the config key `codexSandbox`
(`read-only | workspace-write | danger-full-access`).

If a machine ran the older sandboxed steps, check for ACL debris (`icacls
<dir>` showing `CodexSandboxUsers` or orphan `S-1-5-21-…` entries on the
worktree/SDK) and remove the non-inherited entries.

### 5. Per-repo MCP config missing from the run worktree (all agents)

Claude Code, Gemini, Cursor and Copilot discover the Oracle MCP server from
per-repo files (`.mcp.json`, `.gemini/settings.json`, `.cursor/mcp.json`,
`.vscode/mcp.json`). A run executes in a fresh git worktree — when those files
are gitignored they exist only in the main checkout, and the step agent
silently has no Oracle tools. `FlowWorkspace` now copies these files into the
worktree (best-effort, never overwriting tracked versions).

> How Oracle plugs into agent hosts (Claude Code, Codex, opencode), and the cost/quality reasoning behind the
> design. For the copy-paste agent operating protocol, see the
> [README](../README.md#teaching-your-agent-to-use-oracle); for wiring commands, see [operations.md](operations.md).

## The two seams

An agent host gives Oracle two integration points: an **MCP server** (the tool surface) and **lifecycle
hooks** (automatic capture + injection). Oracle speaks the host's native hook protocol, so the hook receiver
both records the session and returns context to inject.

Capture mirrors how the agents themselves work: a **session** is the agent's own session (keyed by the hook
`session_id`, no lifecycle); each prompt opens a **request** (the user's demand); the agent's work is the
**messages** under that request — `Project → Session → Request → Messages`.

### Inject (synchronous hook responses)

| Hook | What Oracle returns |
|---|---|
| **SessionStart** | The **session identity** (Oracle session id ↔ the agent's session id, so the session can be resumed) + a **session brief** — pending handoff + required rules + top memories. Stable, once per session → lands in the cached prefix (cheap). |
| **UserPromptSubmit** | Opens the **request** (the demand) — embedding its text once and reusing that embedding for a **distance-gated** recall. Nothing is injected when nothing is genuinely relevant — no noise, no prompt-cache churn. |

Injected text is returned as the host's `additionalContext`, which the host renders as a system-reminder
message in the model context.

### Capture (fire-and-forget)

| Hook | What Oracle records |
|---|---|
| **Stop** | The assistant turn (message) under the session's latest request + its token usage (for [metrics](#measurement)). |
| **PostToolUse** | The tool call (truncated) as a message under the latest request + a tool-use metric. |
| **PostCompact** | The compaction summary, persisted as a memory — captured for free at the exact point context is otherwise lost. |

Sessions have **no lifecycle/status** — the agent resumes the same session whenever it wants, so there is
nothing to "close" on `SessionEnd`. The project is resolved from the hook's `cwd`, canonicalized to the
**git root**, so subdirectories and worktrees map to one project.

### MCP instructions

The MCP server advertises a static `instructions` string, which the host auto-injects **once** at connect time
(zero per-turn cost, no tool call). It is the standing "how to use Oracle" guidance. It is kept static so it
never busts the prompt cache; per-project rules are injected per session by the SessionStart hook instead.

## Recall service & cache-awareness

`RecallService` assembles the injected text in two cache-aware shapes:

- `sessionBrief(projectId)` — composes the pending handoff, the **required** rules (`rules_for_task` filtered
  to `severity = required`), and the top memories by importance. Stable across turns.
- `promptRecall(projectId, prompt)` — embeds the prompt and returns memories within a **cosine-distance gate**
  (default `0.6`). Returns nothing when nothing is close, because the plain hybrid search *always* returns some
  nearest-neighbour — "has a hit" is not a relevance signal, distance is.

> **Why the gate matters.** A recall slice that varies every turn, injected into the live (uncached) tail, is
> the opposite of the stable cached prefix the host's prompt caching rewards. Injecting only when relevant —
> and a stable brief at session start — keeps recall from trading a cheap cached prefix for cache misses.

## Cost & quality analysis

### Does it reduce cost? Conditionally.

Prompt caching weakens the naïve "a large always-loaded instructions file is expensive" premise — that file is
read once per session and billed as cache reads (~10× cheaper) thereafter. So:

- **Small, single-repo projects** — caching already amortizes the instructions file; adding an MCP server can
  even *add* cost (it forces the host's system prompt off a global cache scope and adds tool schemas). Net:
  marginal or negative on raw token price.
- **Large / multi-repo / long sessions** (Oracle's target) — the win is real and mostly **indirect**:
  - **Fewer compactions.** Each auto-compaction is a full summarization call (input ≈ the whole conversation)
    plus re-injection of restored attachments. Offloading to recall keeps the window lean and pushes back the
    compaction threshold.
  - **Less re-work across sessions.** Repeated file re-reads and re-derivation are the dominant per-turn cost;
    persistent memory removes them.
  - First-turn / post-clear / post-compact creation cost of a large instructions file, and truncation caps,
    are avoided.

The measurement harness ([operations.md](operations.md#measurement-ab) §) turns this into measured fact:
compare `oracle` vs `baseline` runs by **compactions/session** and **cache-read ratio**.

### Does it improve quality? Yes — and partly independent of cost.

Compaction provably loses verbatim decisions, exact tool outputs, reasoning, and files beyond a small budget.
A persistent verbatim + consolidated store preserves exactly that. Add: a relevant brief from turn one (not a
cold start), rule adherence injected every session, and real semantic recall. The main risk — stale/wrong
memory injected — is mitigated by the lifecycle layer (supersession, decay, retire/forget, lint).

## What it does NOT do

Oracle complements, not replaces, a host's native memory. It targets the cases a flat per-folder memory does
not cover: true semantic search, multi-repo ecosystem scope, a structured rules engine with adherence, a
relational capture model, and deterministic maintenance.
