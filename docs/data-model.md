# Data model (reference)

> The PostgreSQL + pgvector schema: tables, migrations, indexing, search, and lifecycle.

## Overview

One PostgreSQL instance holds both the relational structure and the vector index. Embeddings are
`vector(1024)`; recall is **hybrid** (vector + full-text) fused with Reciprocal Rank Fusion. The schema is
defined by four **forward-only** migrations, which are **embedded in the binary** and applied automatically on
startup — Oracle checks the DB ledger and runs only what is missing, with no migrations folder or configuration
needed. The default database is **`oracle_db`**.

## Tables (11)

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

Capture shape: a **session** is the agent's own session (keyed by `external_id`, no status); each user prompt
opens a **request** (the demand, embedded for semantic search); **messages** are the agent's work and belong to
a request, not directly to a session (`Project → Session → Request → Messages`).

Enumerations are enforced by `CHECK` constraints: memory `tier` ∈ {episodic, semantic, procedural}, `kind` ∈
{decision, gotcha, rule, fact}; rule `severity` ∈ {required, recommended}; message `role`; handoff `status`.

## Migrations

| Version | Adds |
|---|---|
| `v1.0.0/001_baseline` | `001_extensions.sql` (pgvector), `002_tables.sql` (the 10 baseline tables), `003_indexes.sql` (HNSW + GIN + btree + partial unique). |
| `v1.1.0/001_mutation_layer` | `rules.priority`; `retired_at`/`retired_reason` on `rules`/`architectures`/`memories`. |
| `v1.2.0/001_project_resolve` | unique index `uq_projects_repo_path` (race-safe cwd → project upsert). |
| `v1.3.0/001_metrics` | `session_metrics` table + indexes. |

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
