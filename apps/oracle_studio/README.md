# Oracle Studio

Desktop control center for the Oracle AI memory bank (Flutter, Windows-first).
See `docs/desktop-plan.md` at the repo root for the full architecture and phase roadmap.

## What it does (Phase 1)

- Connects straight to the Oracle database by reusing the `oracle_*` Dart packages
  (same `Bootstrap`, DI and usecases the MCP server runs — no API layer).
- Tray-first: closing the window hides to the system tray; quit is explicit from the tray menu.
- Browsers over real data: Dashboard (counts, lint, metrics), Memories (hybrid search),
  Rules (inheritance/override resolved), Skills (central library), Sessions → Requests →
  Messages (capture drill-down), and Backup (portable data-seed, run now).

## Running

```bash
cd apps/oracle_studio
flutter run -d windows        # dev
flutter build windows         # release → build/windows/x64/runner/Release/
```

Configuration comes from the repo-root `.env` (found by walking up from the working
directory or the executable's folder; override with `ORACLE_ENV_PATH`).
