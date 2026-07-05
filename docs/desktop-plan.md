# Oracle Studio — desktop system plan

> The desktop face of Oracle AI: browse and curate everything the memory bank holds, run the
> daemon in the background (tray), schedule backups, configure MCP/hooks, and install the whole
> stack (database included) without Docker. Windows first; macOS/Linux next.

## Why Flutter, and the key architectural win

The entire Oracle backend is **Dart**. The Flutter app therefore imports `oracle_core`,
`oracle_memory` and `oracle_server` **directly** (same pub workspace) and reuses every usecase,
repository, `Bootstrap`, `DbBackupService`, `HooksServer` and `MaintenanceScheduler` — no HTTP
API layer, no serialization drift, one source of truth for business logic.

```
apps/
  oracle_studio/          # Flutter desktop app (this plan)
packages/
  oracle_core/            # shared kernel (db, config, DI, embedders)
  oracle_memory/          # 10 DDD slices (incl. skills)
  oracle_migration/       # forward-only migrations
  oracle_server/          # bootstrap, MCP, hooks, backup, scheduler
```

## Product shape

- **Tray-first background app** (`tray_manager` + `window_manager` + `launch_at_startup`):
  closing the window hides to tray (`setPreventClose`); the tray menu offers Open, Backup now,
  Pause capture, Quit. While running, the app **hosts the hooks daemon + maintenance scheduler +
  backup scheduler** (replacing the console `serve-hooks`) — one background process owns
  everything. Per-agent MCP remains the CLI binary (`serve-mcp`), spawned by each agent.
- **Views** (read + curate): Dashboard (status, metrics, lint), Products & Projects, Memories
  (search/inspect/forget/supersede), Rules (priority/retire), Skills (edit, sync-skills),
  Architectures, Sessions → Requests → Messages (capture browser), Handoffs, Maintenance
  (lint/run/reembed), Backup (run now, schedule interval/daily, restore wizard with the
  non-destructive guard), Settings (.env editor, embedder provider + API key test, hook token,
  MCP snippet generator with copy button).
- **UI language**: pt-BR strings first, structured for l10n (en next).

## Setup wizard (installer) — also Flutter

A separate small Flutter app (`apps/oracle_setup`) — wizard steps:

1. **Welcome / license** → install dir (`%LOCALAPPDATA%\OracleAI`).
2. **Database**: detect in order — existing PostgreSQL (test connection) → Docker (compose up)
   → **bundled portable PostgreSQL** (no Docker needed): unzip official postgresql.org binaries
   (EDB zip) + prebuilt Windows pgvector (vector.dll → `lib/`, vector.control + sql → `share/
   extension/`), `initdb`, pick a free port (5433+), start via `pg_ctl register` (Windows
   service) or child process. Store choice in `.env`.
3. **Embedder**: local (offline, default) or Gemini/OpenAI/Voyage + API key (validated live).
4. **Security**: generate `ORACLE_HOOK_TOKEN`, write `.env`.
5. **Migrate + seed**: run migrations; optionally restore a `.sql` seed (team onboarding).
6. **Agent wiring**: write `.mcp.json` + hooks settings for Claude Code (and print snippets for
   Codex/Cursor); run `sync-skills`.
7. **Finish**: install Studio to autostart (tray), launch it.

Distribution: Inno Setup produces the single `OracleAI-Setup.exe` that unpacks payload
(Studio + CLI binary + PG zip + pgvector) and launches the Flutter wizard. MSIX later for the
Store path.

## Backup scheduling

Studio's scheduler (persisted in settings): interval or daily-at-time, retention (keep last N),
target folder, "backup before maintenance" toggle. Uses `DbBackupService` directly — the same
snapshot-consistent, restore-verified engine, plus tray "Backup now".

## Phases

| Phase | Scope | Exit criteria |
|---|---|---|
| 0 ✅ | Skills backend (v1.7.0), research, this plan | verified on live DB |
| 1 ✅ | Studio scaffold: workspace app, tray shell, DB connect, Dashboard + read-only browsers (memories/rules/skills/sessions) | browse real data |
| 2 ✅ | Curation actions + global search + Skills editor with sync | edit round-trips verified |
| 3 ✅ | Studio hosts hooks daemon + schedulers; Backup UI + scheduling; Settings/.env + MCP generator | console daemon retired |
| 4 ✅ | Setup wizard incl. portable PG provisioning | clean-machine install works |
| 5 ✅ | Packaging (Inno Setup → single `OracleAI-Setup.exe`), l10n en, DPAPI-encrypted secrets, Untitled-UI polish | installer builds & runs; macOS/Linux adaptation still open |

> **Status:** phases 0–5 delivered — Studio is a full tray control center and the single-file
> `OracleAI-Setup.exe` installs the whole stack (bundled PostgreSQL + pgvector, no Docker) per-user with
> encrypted secrets. Remaining: macOS/Linux adaptation (Keychain / Secret Service, native shortcuts,
> packaging) and MSIX for the Store path.
