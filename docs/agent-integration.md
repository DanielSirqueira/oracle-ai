# Agent integration

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
