# MCP tools (reference)

> The 32 tools exposed by the MCP server (stdio). Each is wired to a use case via DI; arguments map to the use
> case input, and the result is returned as JSON (errors carry `isError`).

The server also advertises static MCP **`instructions`** that the client auto-injects once at connect time —
short standing guidance on how to use these tools. For the agent-facing operating protocol, see
[agent-integration.md](agent-integration.md).

## Status

| Tool | Args | Description |
|---|---|---|
| `oracle_status` | — | Server name/version/health. |

## Scope — products & projects

| Tool | Args | Description |
|---|---|---|
| `oracle_product_register` | `name`, `description?` | Register a product (ecosystem scope). |
| `oracle_product_list` | `search?`, `limit?` | List products. |
| `oracle_project_register` | `name`, `description?`, `repoPath?` | Register a project. |
| `oracle_project_list` | `search?`, `limit?` | List projects. |
| `oracle_project_resolve` | `repoPath`, `name?`, `productId?` | **Get-or-create** a project from a working directory (canonicalized to git root). Returns the `projectId` used by every other call. |
| `oracle_session_brief` | `repoPath?` / `projectId?` | **Call this first.** Resolves the project from your cwd and returns the `projectId` + a brief (pending handoff + required rules + key memories). The hook-free way to get oriented at session start. |

## Architecture

| Tool | Args | Description |
|---|---|---|
| `oracle_architecture_save` | `projectId`, `area`, `content` | Save/refine the architecture page for an area (re-saving supersedes). |
| `oracle_architecture_get` | `projectId`, `area` | Current architecture page for an area. |
| `oracle_architecture_search` | `query`, `projectId?`, `area?`, `limit?` | Hybrid search over architecture. |
| `oracle_architecture_retire` | `id`, `reason?`, `hard?` | Retire (soft) or purge (`hard:true`) a page. |

## Rules

| Tool | Args | Description |
|---|---|---|
| `oracle_rule_save` | `projectId?`/`productId?`, `key`, `scope`, `title`, `content`, `severity?`, `priority?`, `tags?` | Create/refine a rule (re-saving the same `key` supersedes). |
| `oracle_rules_for_task` | `projectId`, `scope?`, `limit?` | Applicable rules for a task (product→project inheritance + override), ordered by severity then priority. |
| `oracle_rule_search` | `query`, `projectId?`, `productId?`, `scope?`, `severities?`, `limit?` | Hybrid search over rules. |
| `oracle_rule_set_priority` | `id`, `priority` | Re-rank a rule in place (no new version). |
| `oracle_rule_retire` | `id`, `reason?`, `hard?` | Retire (soft) or purge a rule. |

## Memory

| Tool | Args | Description |
|---|---|---|
| `oracle_memory_save` | `projectId?`/`productId?`, `tier?`, `kind?`, `title`, `body`, `tags?`, `importance?` | Save a consolidated memory. `tier` ∈ episodic/semantic/procedural; `kind` ∈ decision/gotcha/rule/fact. |
| `oracle_memory_search` | `query`, `projectId?`, `productId?`, `tiers?`, `kinds?`, `limit?` | Hybrid search (vector + full-text, RRF). |
| `oracle_memory_get` | `id` | Fetch a memory (bumps access counters). |
| `oracle_memory_forget` | `id`, `reason?`, `hard?` | Forget (soft, audited) or purge a memory. |

## Continuity — handoffs & history

| Tool | Args | Description |
|---|---|---|
| `oracle_handoff_begin` | `projectId`, `summary`, `fromAgent?`, `toAgent?`, `sourceSessionId?`, `openQuestions?`, `nextSteps?`, `filesTouched?`, `cwd?` | Write a handoff for the next session/agent. |
| `oracle_handoff_pending` | `projectId` | Pending handoffs for a project (inject on session start). |
| `oracle_handoff_accept` | `id` | Accept (consume) a handoff. |
| `oracle_session_recent` | `projectId`, `limit?` | Recent sessions for a project. |
| `oracle_session_history` | `sessionId`, `limit?` | All messages of a session in order (across every request). |
| `oracle_session_requests` | `sessionId`, `limit?` | The user demands (requests) made in a session, newest first. |
| `oracle_request_messages` | `requestId`, `limit?` | The agent work (messages) carrying out one specific request. |
| `oracle_request_search` | `projectId`, `query`, `limit?` | Semantic search over past **user demands** — "has the user asked for this before?" |

## Maintenance

| Tool | Args | Description |
|---|---|---|
| `oracle_maintenance_run` | `dryRun?`, `decay?`, `dedup?`, `tiers?`, `staleDays?`, `minImportance?`, `minAccessCount?`, `dedupDistance?`, `limit?` | Deterministic sweep over memories (decay + dedup). `dryRun:true` previews. |
| `oracle_maintenance_lint` | — | Read-only health check (memories/rules without embedding, old user demands with no agent work). |

## Measurement

| Tool | Args | Description |
|---|---|---|
| `oracle_metrics_summary` | `label?` | Aggregate per experiment label: tokens, cache-read ratio, compactions/session. |
| `oracle_metrics_session` | `projectId`, `limit?` | Recent per-session metric rows. |
