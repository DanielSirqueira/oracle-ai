# Oracle AI — documentation

Deeper material that complements the top-level [README](../README.md). Organized by purpose.

## Explanation — understand the project
- [vision.md](vision.md) — the concept (the "LLM Wiki" idea), the problem, the five pillars, and the core
  design decisions.
- [architecture.md](architecture.md) — Clean Architecture + DDD layering, the workspace packages, the ten
  feature slices, and the runtime topology.

## Reference — look things up
- [data-model.md](data-model.md) — the PostgreSQL + pgvector schema: tables, migrations, indexing, hybrid
  search, and the lifecycle model.
- [mcp-tools.md](mcp-tools.md) — the MCP tools (incl. the 13 `oracle_rfc_*` spec-review tools), grouped by domain, with their arguments.

## Guides — get things done
- [agent-integration.md](agent-integration.md) — how Oracle plugs into agent hosts (hooks + MCP), the recall
  service, and the cost/quality analysis.
- [operations.md](operations.md) — the runbook: build, run, connect an agent, deploy the shared daemon, and run
  the cost A/B experiment.
- [desktop-plan.md](desktop-plan.md) — the desktop layer: Oracle Studio (tray control center) and the single
  `OracleAI-Setup.exe` installer (bundled PostgreSQL, DPAPI-encrypted secrets).
- [loop-engineering-plan.md](loop-engineering-plan.md) — **v2.2.0 (Fase 1 implementada)**: Loop Engineering —
  flows de desenvolvimento multi-agente (tasks → runner → loops por etapa), análise completa + plano (em PT-BR).

## Start here
New to the project? Read [vision.md](vision.md) → [architecture.md](architecture.md), then jump to
[operations.md](operations.md) to run it.
