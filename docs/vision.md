# Vision & concepts

> Why Oracle AI exists, the problem it solves, and the principles that shape it.

## The "LLM Wiki" idea

LLMs are stateless between sessions. Andrej Karpathy framed the fix as an **"LLM Wiki"**: a curated knowledge
base that the model **reads from and writes to**, so knowledge **accumulates** over time instead of evaporating
at the end of each conversation. Oracle AI is the engineering realization of that idea for **coding agents** —
backed by a relational + vector store (PostgreSQL + pgvector) and exposed over MCP.

## The problem

Agent harnesses approximate memory two ways, and both have hard limits:

1. **A static instructions file** (`CLAUDE.md`, `AGENTS.md`, …) loaded in full every session. It is cheap in
   steady state (prompt caching) but does **not scale** to a large, multi-repository knowledge base, and it
   hits truncation caps.
2. **Context compaction** — a lossy summarization that fires when the window fills, discarding the live history
   (exact tool outputs, reasoning, decisions) in exchange for a prose summary. It **provably loses** context
   the agent still needed, and each compaction is an expensive extra model call.

The recurring cost is **re-work**: the agent re-reads files, re-derives decisions, and re-learns conventions
every session because nothing durable persists between them.

## What Oracle AI does

An external memory the agent **queries on demand** and **writes to as it works**:

- **Persists** — verbatim raw capture (sessions/messages) **plus** consolidated memory (decisions, gotchas,
  rules-learned) — what compaction throws away.
- **Recalls semantically** — the relevant slice for the task, via hybrid (vector + full-text) search, instead
  of loading everything every turn.
- **Spans an ecosystem** — a `product → project` hierarchy, so memory and rules cover many repositories with
  inheritance and override.
- **Enforces rules** — development rules with severity and priority, resolved per task and injected so agents
  actually follow them.
- **Is shared** — one store across agents and sessions, so knowledge compounds.

## The five pillars

1. **Embeddings brain** — semantic recall over a hybrid index, not keyword grep.
2. **Force recall** — deep, structured retrieval the agent leans on instead of re-deriving context.
3. **Ecosystem memory** — `product → project`, spanning repositories, with inheritance and override.
4. **Persistent rules engine** — rules with adherence, injected automatically.
5. **Corporate memory** — one shared store; knowledge compounds across agents.

## Core design decisions

- **PostgreSQL + pgvector as the single primary store.** Relational structure (scope hierarchy, sessions,
  rules) and vector recall live together. The ecosystem scale and broad capture justify a real database over a
  file-based store.
- **No consolidation LLM.** The **agent itself** consolidates — it already holds the short-term context — by
  calling a strict-schema MCP tool (`oracle_memory_save`) at task boundaries. The server only performs
  **deterministic, explainable** maintenance (dedup / decay / supersession). The only external dependency is
  the embeddings API, and even that is optional (a local offline embedder ships in).
- **Versioned, non-destructive lifecycle.** Knowledge is *superseded* (kept as history) or *retired* (soft,
  audited), with an explicit *purge* for true deletion. "Bad memory is worse than no memory" — so retire/decay
  and lint exist to keep the store healthy.
- **Cache-aware injection.** Recall is injected at a *stable* position (session start) or *gated* by relevance,
  never as a per-turn-varying tail — so it never trades a cheap cached prefix for expensive cache misses.

See [architecture.md](architecture.md) for how these map to code, and
[agent-integration.md](agent-integration.md) for the cost/quality analysis that backs them.
