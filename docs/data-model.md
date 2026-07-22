# Data model (reference)

> The PostgreSQL + pgvector schema: tables, migrations, indexing, search, and lifecycle.

## Overview

One PostgreSQL instance holds both the relational structure and the vector index. Embeddings are
`vector(1024)`; recall is **hybrid** (vector + full-text) fused with Reciprocal Rank Fusion. The schema is
defined by eight **forward-only** migrations, which are **embedded in the binary** and applied automatically on
startup — Oracle checks the DB ledger and runs only what is missing, with no migrations folder or configuration
needed. The default database is **`oracle_db`**.

## Tables (12)

| Table | Purpose | Notable columns |
|---|---|---|
| `products` | Ecosystem scope (cross-repo) | `name`, `description` |
| `projects` | Central scope unit | `product_id?` (nullable FK), `repo_path` (unique; cwd → project) |
| `architectures` | Architecture pages per area | `project_id`, `area`, `content`, `embedding`, `is_latest`, `supersedes`, `retired_at`/`retired_reason` |
| `rules` | Development rules | `product_id?`/`project_id?`, `key`, `scope`, `severity`, `priority`, `content`, `embedding`, `fts`, `is_latest`, `supersedes`, `retired_at`/`retired_reason` |
| `sessions` | The agent's own session (no lifecycle) | `project_id`, `agent`, `external_id` (the agent's session id), `cwd`, `created_at`; `UNIQUE(project_id, agent, external_id)` |
| `requests` | One user demand (per prompt) within a session | `session_id`, `user_text`, `embedding`, `fts`, `created_at` |
| `messages` | Agent work carrying out a request | `request_id` (NOT NULL), `role`, `content`, `token_count`, `embedding?`, `created_at` |
| `agent_events` | Agent work (polymorphic) | `request_id`, `kind` (step/reasoning/query/decision/action), `content`, `position`, `embedding?` |
| `memories` | Consolidated memory | `product_id?`/`project_id?`, `tier`, `kind`, `title`, `body`, `importance`, `embedding`, `fts`, `is_latest`, `supersedes`, `superseded_at`, `access_count`, `last_accessed_at`, `retired_at`/`retired_reason` |
| `handoffs` | Continuity baton | `project_id`, `summary`, `open_questions`/`next_steps`/`files_touched` (jsonb), `status` |
| `session_metrics` | Measurement harness | `project_id`, `external_id`, `label`, token counters, `compactions`, `tool_uses`, `turns` |
| `skills` | Central shared skill library | `product_id?`/`project_id?`, `key`, `name`, `description`, `content`, `embedding`, `fts`, `is_latest`, `supersedes`, `usage_count`, `retired_at`/`retired_reason` |

Capture shape: a **session** is the agent's own session (keyed by `external_id`, no status); each user prompt
opens a **request** (the demand, embedded for semantic search); **messages** are the agent's work and belong to
a request, not directly to a session (`Project → Session → Request → Messages`).

Enumerations are enforced by `CHECK` constraints: memory `tier` ∈ {episodic, semantic, procedural}, `kind` ∈
{decision, gotcha, rule, fact}; rule `severity` ∈ {required, recommended}; message `role`; handoff `status`.

## RFC — multi-agent spec review (v2.1.0)

Ten tables back the RFC deliberation engine (migration `v2.1.0/001_rfc`), following the same conventions as the
rest of the schema: uuid PK, `timestamptz`, `vector(1024)` + `embedding_model`, generated `fts`,
`is_latest`/`supersedes`, an owner `CHECK` across `organization_id`/`project_id`/`module_id`, and HNSW + GIN
indexes.

| Table | Purpose | Notable columns |
|---|---|---|
| `rfcs` | RFC header (a spec published for review) | `organization_id?`/`project_id?`/`module_id?` (owner CHECK), `title`, `rfc_type`, `status`, `current_version_id` (FK → `rfc_versions`), `author_agent`, `round_count`, `supersedes` |
| `rfc_versions` | One consolidation round of the document | `rfc_id`, `version_no`, `summary`, `embedding`, `fts`, `is_latest`, `supersedes` |
| `rfc_sections` | The sectioned body (the checklist) | `version_id`, `section_key`, `content`, `required`, `coverage` (missing/thin/covered), `embedding`, `fts` |
| `rfc_comments` | A structured finding (the core) | `rfc_id`, `version_id`, `section_id?`, `type`, `severity`, `problem`, `proposed_solution`, `confidence`, `status`, `verified`, `parent_comment_id`, `embedding` (dedup/novelty), `fts` |
| `rfc_comment_evidence` | Verifiable grounding for a finding | `comment_id`, `kind`, `ref_kind` (oracle_entity/file/external), `ref_id?` (polymorphic), `locator`, `excerpt`, `resolved` |
| `rfc_comment_relations` | Typed argumentation graph | `from_comment`, `to_comment`, `relation`, `ground`, `reason`, `evidence` (jsonb) |
| `rfc_comment_resolutions` | Finding resolution + audit | `comment_id`, `decision`, `ground`, `reason`, `rule_id?` |
| `rfc_rounds` | A review round | `rfc_id`, `version_id?`, `round_no`, `participants` (text[]), `new_criticals`, `new_majors`, `novelty_score` |
| `rfc_decisions` | Decisions (incl. product) + write-back | `rfc_id`, `question`, `chosen_option`, `rationale`, `comment_ids` (jsonb), `human_approved`, `memory_id?` (→ `memories`) |
| `rfc_participants` | Per-(agent,role) calibration substrate | `rfc_id`, `agent`, `role`, `model`, `comments_posted`, `accepted`, `invalidated` |

**Status lifecycle** (`rfcs.status` CHECK): `draft → open_for_comments → in_review ⇄ in_consolidation`, with
`awaiting_human` (product decision / unresolved conflict) and `stalled` (budget) branches, terminating in
`approved`/`rejected`, later `superseded`/`obsolete`. **Evidence gating:** a finding is `verified` only when it
cites an entity that resolves (an `oracle_entity` id that exists, or a `file`+`excerpt` that matches);
`oracle_rfc_finalize` approves only with **0 verified criticals + every required section covered**, then writes
each decision back to `memories(kind=decision)` — closing the learning loop.

## Loop Engineering — multi-agent development flows (v2.2.0)

Nine tables back the Loop Engineering engine (migration `v2.2.0/001_flows`), following the same
conventions: uuid PK, `timestamptz`, an owner `CHECK` across `organization_id`/`project_id`/
`module_id` where the row is scoped, `is_latest`/`supersedes` for the versioned `flows`, `CHECK`
enums matching the Dart enum codes, and `vector(1024)` + generated `fts` on `tasks`. **No existing
table changed** — the seams are new FKs (`tasks.rfc_id → rfcs`, `flow_run_steps.session_id →
sessions`).

| Table | Purpose | Notable columns |
|---|---|---|
| `tasks` | The backlog that triggers flows | `organization_id?`/`project_id?`/`module_id?` (owner CHECK), `title`, `status`, `priority`, `source`, `rfc_id?`, `embedding`, `fts`; at most one active root run per task |
| `flows` | The process definition (the "n8n workflow"), versioned by `key` | `orchestrator_agent`, `entry_step_key`, `budgets` (jsonb), `version_no`, `is_latest`, `supersedes` |
| `flow_steps` | The nodes — each node is a loop | `flow_id`, `step_key`, `kind` (agent/orchestrator/decision/rfc_create/rfc_review/rfc_consolidate/rfc_gate/subflow/command/human_gate), `agent`, `role`, `prompt_template`, `exit_criteria`/`output_schema`/`permissions`/`config` (jsonb), `max_iterations`, `on_fail` |
| `flow_edges` | The edges (wiring between loops) | `from_step`, `to_step`, `condition` (success/failure/verdict/always), `verdict_value`, `instruction` (when to take a verdict route — rendered into the source agent's prompt, so ANY node can decide) |
| `flow_runs` | A running instance (pins the flow version) | `flow_id`, `task_id?`, `project_id?`, `parent_run_id?`, `status`, `current_step_id?`, `execution_state`, `lease_epoch`, `branch_name`, `worktree_path`, `budgets`, `tokens_used`, `claimed_by`, `heartbeat_at` |
| `flow_run_steps` | Each iteration of each step (the inner loop) | `run_id`, `step_id`, `iteration`, `status` (including `abandoned` after reclaim), `session_id?` (→ Oracle transcript), `agent_session_id?` (native Claude/Codex/Gemini/Cursor conversation resumed by later iterations), `claim_token`, `report`/`verifier` (jsonb) |
| `flow_run_context` | The run's blackboard (key→value) | `run_id`, `key`, `value` (jsonb), `updated_by?`; PK `(run_id, key)` |
| `flow_artifacts` | What a run produced, by reference | `run_id`, `run_step_id?`, `kind` (branch/commit/pr/rfc/doc/memory…), `locator`, `meta` (jsonb) |
| `flow_run_events` | Append-only timeline (audit + Studio) | `run_id`, `run_step_id?`, `kind` (state/verifier/decision/gate/budget…), `payload` (jsonb) |

**Run lifecycle** (`flow_runs.status` CHECK): `queued → running`, branching to `awaiting_human` (a
human gate / product decision), `paused` (control), `stalled` (budget / no-progress), and
terminating in `completed`/`failed`/`cancelled`. The **Flow Runner** claims the oldest `queued` run
with `FOR UPDATE SKIP LOCKED`, so two workers never grab the same run; the entire run state lives in
these tables, so a killed worker resumes from the last event. Verifiers run **outside** the agent
(the runner executes each step's `exit_criteria` in the worktree), so an agent can never
self-approve. See [architecture.md](architecture.md) §Flow Runner and
[loop-engineering-plan.md](loop-engineering-plan.md).

Starting a root run atomically locks the task, creates the run and moves the task to `running`. Another active
root run for the same task is rejected even under concurrent requests. A failed run may be retried sequentially
after the task becomes `blocked`; `done` and `cancelled` tasks remain terminal and require a new task. Child
subflows remain part of the original run and may keep the same task reference.

Before an agent process is launched, the runner creates a deterministic Oracle `session` per run node, opens a
new `request` for the iteration and links it to `flow_run_steps.session_id`. The final output is appended as a
message. The external CLI conversation id is stored separately in `agent_session_id`: Claude Code/Gemini start
with a runner-selected id; Codex/Cursor return theirs in structured output. Later iterations of that node use
the CLI's resume command. Both transcript and native context survive pause, worker restart and graph loop-back.

`execution_state` checkpoints the graph frontier (queue, active step, waits,
visits and join arrivals). `lease_epoch` increments on every claim, fencing a
stale worker from overwriting a pause, cancellation or newer recovery.

## Migrations

| Version | Adds |
|---|---|
| `v1.0.0/001_baseline` | `001_extensions.sql` (pgvector), `002_tables.sql` (the 10 baseline tables), `003_indexes.sql` (HNSW + GIN + btree + partial unique). |
| `v1.1.0/001_mutation_layer` | `rules.priority`; `retired_at`/`retired_reason` on `rules`/`architectures`/`memories`. |
| `v1.2.0/001_project_resolve` | unique index `uq_projects_repo_path` (race-safe cwd → project upsert). |
| `v1.3.0/001_metrics` | `session_metrics` table + indexes. |
| `v1.4.0/001_request_index` | composite `idx_requests_session (session_id, created_at DESC)` for the hot capture path. |
| `v1.5.0/001_search_hygiene` | `requests.embedding_model`; a stored generated `fts` column + GIN on `architectures` (was an inline per-row tsvector). |
| `v1.6.0/001_memory_key` | `memories.key` — the same stable-key identity rules have, so an agent can supersede a memory by key. |
| `v1.7.0/001_skills` | `skills` table (central versioned skill library) + HNSW/GIN/partial-unique indexes. |
| `v2.1.0/001_rfc` | The 10 RFC tables (multi-agent spec review) + HNSW/GIN/partial-unique indexes; embedded migrations regenerated. |
| `v2.2.0/001_flows` | The 9 Loop Engineering tables (tasks + flows + runs) across 4 SQL files + HNSW/GIN/partial-unique indexes; embedded migrations regenerated. |
| `v2.2.8/001_agent_session_resume` | Adds `flow_run_steps.agent_session_id` and its lookup index so native agent conversations continue across loop iterations. |
| `v2.2.9/001_active_task_run_unique` | Adds a partial unique index guaranteeing at database level that a task has at most one active root run; terminal history remains available for sequential retries. |

The runner records applied migrations and checksums in `_migrations`, serializes with `_migrations_lock` (an
advisory lock with a 2-minute stale-takeover), runs each migration transactionally, and is **forward-fix**
(no down migrations). It tolerates concurrent startup (lock retry with backoff).

## Indexing & search

- **Vector recall** — HNSW per embedded column (`vector_cosine_ops`, `m=16`, `ef_construction=64`), queried
  with the `<=>` cosine operator.
- **Full-text** — `tsvector` columns (`fts`, generated) with GIN indexes; tags use GIN too.
- **Scope/keys** — btree on FKs; **partial unique** indexes `WHERE is_latest` enforce one current version per
  key/area (e.g. `uq_rules_project_latest` on `(project_id, key)`).
- **Hybrid search** — a CTE ranks the semantic leg (by `<=>`) and the lexical leg (by `ts_rank_cd` /
  `websearch_to_tsquery`) over a bounded candidate pool, then fuses them with **Reciprocal Rank Fusion**
  (RRF, `k=60`). It degrades gracefully to semantic-only or keyword-only when one input is missing.

> **Driver note:** pgvector returns `vector` as binary, so read paths cast `embedding::text` for parsing while
> a scoped CTE keeps the raw vector for the `<=>` distance.

## Lifecycle — three orthogonal axes

Knowledge is never blindly overwritten. Three independent axes keep concerns separate:

1. **Severity** (`required` / `recommended`) — obligation. *Must follow* vs *should follow*.
2. **Priority** (0..100) — ranking/relevance within a severity. Re-rankable in place, without a new version.
3. **Lifecycle status** — existence:
   - **active + latest** — `is_latest = true`.
   - **superseded** — replaced by a newer version of the same key/area (`is_latest = false`, kept as history).
   - **retired** — deliberately removed, no replacement (`is_latest = false` + `retired_at`/`retired_reason`),
     reversible and audited.
   - **purged** — a hard `DELETE` for true junk / sensitive data.

Recall filters on `is_latest`, so superseding or retiring drops a row out of every recall path automatically.

## Inheritance & override

Rules (and memories) belong to a **product** OR a **project**. `rules_for_task` resolves
`product → project` inheritance with override: project-scoped rules win over product rules of the same `key`
(`SELECT DISTINCT ON (key) … ORDER BY key, (project_id IS NOT NULL) DESC`), then orders the result by
`severity = required` first, then `priority DESC`, then title.

## Decay substrate

`memories` carry `importance`, `access_count`, and `last_accessed_at`. Reads bump the access counters; the
maintenance sweep uses them (with tier) to forget stale, low-value, rarely-accessed memories. Episodic
memories are eligible for decay by default; semantic/procedural are treated as durable. See
[architecture.md](architecture.md) and the `maintenance` slice.
