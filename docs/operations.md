# Operations runbook

> Run Oracle, connect it to your agent, deploy the shared daemon, and run the cost A/B experiment.

## 0. Prerequisites

- **Docker** (for PostgreSQL + pgvector).
- **Dart SDK ≥ 3.11** (to build; or use Docker only).
- Optional: an embedding API key (Gemini / OpenAI / Voyage). Without one it runs the `local` offline embedder.

## 1. Start PostgreSQL + pgvector

The `pgvector/pgvector:pg17` image is in `docker-compose.yml`. If port 5432 is taken, pick another via
`ORACLE_DB_PORT`.

```bash
ORACLE_DB_PORT=5435 docker compose up -d db        # POSIX
```
```powershell
$env:ORACLE_DB_PORT='5435'; docker compose up -d db   # PowerShell
```

Confirm: `docker ps` shows `oracle_ai-db-1` healthy.

## 2. Configure

Copy `.env.example` to `.env` and adjust (or export as process env, which overrides `.env`). Minimum:

```ini
ORACLE_DB_HOST=localhost
ORACLE_DB_PORT=5435
ORACLE_DB_NAME=oracle_db          # default; you can omit it
ORACLE_DB_AUTO_CREATE=true        # create the db if missing
ORACLE_EMBEDDING_PROVIDER=local   # or gemini/openai/voyage (+ the matching *_API_KEY)
ORACLE_HTTP_PORT=49500            # hook receiver port
ORACLE_METRICS_ENABLED=true
ORACLE_METRICS_LABEL=oracle       # experiment tag (see §6)
```

## 3. Build the native binary

```bash
dart pub get
mkdir -p build
dart compile exe packages/oracle_server/bin/oracle_ai.dart -o build/oracle_ai      # .exe on Windows
```
Alternative without compiling: `dart run oracle_server:oracle_ai <args>` (slower startup).

### Binary modes

| Command | Behavior |
|---|---|
| `oracle_ai` | All-in-one: migrate + hook receiver + scheduler + MCP (stdio). Good for one machine / one agent. |
| `oracle_ai serve-hooks` | **Shared daemon**: migrate + hook receiver + scheduler, runs until SIGINT/SIGTERM. No MCP (see §7). |
| `oracle_ai serve-mcp` | MCP (stdio) only, **no hooks** — what each agent spawns when the daemon owns the hooks (§7). |
| `oracle_ai migrate` | Run migrations, then exit. |
| `oracle_ai install-mcp [binary-path]` | Print the `.mcp.json` snippet. |
| `oracle_ai install-hooks` | Print the `settings.json` hooks block. |

## 4. Initialize the database

```bash
./build/oracle_ai migrate            # expect: migrations: applied=4 ... ok   (v1.0.0..v1.3.0)
```

## 5. Connect your agent

### 5.0 Simplest — one global MCP server (recommended)

Oracle is a **cross-project** memory bank, so register it **once, globally** (user scope) and it is available
in every repo — no per-project files, no hooks, a single MCP connection. The agent calls `oracle_session_brief`
at the start of work to get oriented (the auto-injected MCP `instructions` tell it to). `serve-mcp` runs MCP
only (it never opens the hook receiver).

The config is tiny: **migrations are embedded** in the binary (applied on startup — nothing to configure) and
the **database name defaults to `oracle_db`**, so you only say *where* the DB is and pass the embedding key:

```bash
claude mcp add oracle-ai --scope user --transport stdio \
  -e ORACLE_DB_PORT=5435 \
  -e ORACLE_DB_AUTO_CREATE=true \
  -e ORACLE_EMBEDDING_PROVIDER=gemini \
  -e GEMINI_API_KEY=YOUR_KEY \
  -- /abs/path/to/build/oracle_ai serve-mcp
```

That writes a user-scoped entry to `~/.claude.json`. Equivalent manual JSON:

```jsonc
{ "mcpServers": { "oracle-ai": {
    "type": "stdio",
    "command": "/abs/path/to/build/oracle_ai",
    "args": ["serve-mcp"],
    "env": {
      "ORACLE_DB_PORT": "5435",             // omit if your pgvector is on the default localhost:5432
      "ORACLE_DB_AUTO_CREATE": "true",       // creates oracle_db on first run
      "ORACLE_EMBEDDING_PROVIDER": "gemini",
      "GEMINI_API_KEY": "..."
    }
} }}}
```

Defaults you never set: DB host `localhost`, name `oracle_db`, embedding dim `1024`; migrations are internal.
That is the whole agent-facing config. What you trade away vs. the full setup: automatic raw capture and
automatic SessionStart/UserPromptSubmit injection — but the agent still saves consolidated memory and pulls the
brief/recall itself via tools (the high-value path). Add the hooks below only if you want capture + injection
to be automatic.

### 5.1 Optional — add hooks for automatic capture + injection

The host **spawns the MCP server over stdio**; in the all-in-one mode (`args: []`) **that same process opens the
hook receiver (HTTP)**; the `http` hooks in `settings.json` POST to it. Generate and merge into `.mcp.json`
(project root):
```bash
./build/oracle_ai install-mcp ./build/oracle_ai
```
```jsonc
{ "mcpServers": { "oracle-ai": {
    "type": "stdio",
    "command": "/abs/path/to/build/oracle_ai",
    "args": [],
    "env": { "ORACLE_METRICS_LABEL": "oracle" }   // optional, for the A/B (§6)
}}}
```

**5.2 Hooks** — generate and merge the `hooks` block into your host's `settings.json`:
```bash
./build/oracle_ai install-hooks
```
This registers **SessionStart**/**UserPromptSubmit** (synchronous → inject the brief and recall) and
**Stop**/**PostToolUse**/**PostCompact**/**SessionEnd** (async → capture + metrics).

**5.3 Teach the agent.** Paste the operating protocol from the
[README](../README.md#teaching-your-agent-to-use-oracle) into your `CLAUDE.md` (Claude Code) or `AGENTS.md`
(Codex / opencode). With hooks installed, the SessionStart brief and the MCP `instructions` are injected
automatically; the protocol reinforces it and is portable across hosts.

> **Codex / others:** same `.mcp.json` + hooks. In multi-agent use each spawns its own process; only the first
> binds the hook port (the rest serve MCP without hooks, no crash).

## 6. Measurement (A/B) <a id="measurement-ab"></a>

Compare the **same workload** with and without Oracle's help, then read the numbers.

**6.1 Baseline run (Oracle measures but doesn't help):**
- In `settings.json`, **remove** the **SessionStart** and **UserPromptSubmit** hooks (keep only capture).
- In `.mcp.json`, set `"env": { "ORACLE_METRICS_LABEL": "baseline" }`.
- Run K representative sessions.

**6.2 Oracle run (Oracle helps):**
- Restore **all** hooks (inject + capture).
- `"env": { "ORACLE_METRICS_LABEL": "oracle" }`.
- Run the K equivalent sessions.

**6.3 Read the result** — ask the agent to call `oracle_metrics_summary`, or run SQL directly:
```bash
docker exec oracle_ai-db-1 psql -U postgres -d oracle_ai -c "
  SELECT label, count(*) AS sessions,
    round(sum(cache_read_tokens)::numeric
      / NULLIF(sum(input_tokens+cache_creation_tokens+cache_read_tokens),0), 4) AS cache_read_ratio,
    round(avg(compactions)::numeric, 2) AS avg_compactions_per_session,
    round(avg(input_tokens+output_tokens+cache_creation_tokens+cache_read_tokens)::numeric, 0) AS avg_tokens_per_session
  FROM session_metrics GROUP BY label ORDER BY label;"
```

**6.4 Interpret.** Oracle reduces cost if the `oracle` label shows **fewer compactions/session** (the
expensive event) and **fewer tokens/session** while keeping a **high cache-read ratio**. If the ratio drops
sharply under `oracle`, injection is breaking cache — keep the brief stable at SessionStart and per-turn recall
small and gated.

## 7. Production: shared hooks daemon

For a shared machine / multi-agent setup, run **one daemon** that owns the hooks + scheduler + migrations;
per-agent MCP processes run `serve-mcp` (no hooks).

```bash
docker compose -f docker-compose.prod.yml up -d --build
docker compose -f docker-compose.prod.yml logs -f oracle   # "hooks HTTP on 0.0.0.0:49500"
```

`docker-compose.prod.yml` brings up **db** (pgvector, named volume, published port for host-native MCP) and
**oracle** (`command: ["serve-hooks"]`, `ORACLE_HTTP_HOST=0.0.0.0`, publishes `49500`,
`ORACLE_MAINTENANCE_INTERVAL_MINUTES=30`, `restart: unless-stopped`).

- **Hooks (host):** same `install-hooks` (they point at `http://127.0.0.1:49500/hook`, now served by the daemon).
- **MCP per agent** — two `.mcp.json` options:
  - **(a) Host-native binary** — connects to the published DB:
    ```jsonc
    { "mcpServers": { "oracle-ai": { "type": "stdio",
        "command": "/abs/path/build/oracle_ai", "args": ["serve-mcp"],
        "env": { "ORACLE_DB_HOST": "localhost", "ORACLE_DB_PORT": "5432" } }}}
    ```
  - **(b) Inside the container** (stays on the compose network):
    ```jsonc
    { "mcpServers": { "oracle-ai": { "type": "stdio", "command": "docker",
        "args": ["exec","-i","oracle_ai_prod-oracle-1","/app/oracle_ai","serve-mcp"] }}}
    ```

In both, the MCP uses `serve-mcp` → it does not try to bind the hook port (the daemon owns it). The maintenance
scheduler runs only in the daemon (one place, no per-agent duplication).

## 8. Maintenance

- On demand: `oracle_maintenance_run` (use `dryRun:true` to preview) and `oracle_maintenance_lint`.
- Automatic: `ORACLE_MAINTENANCE_ON_STARTUP=true` (once on boot) and/or `ORACLE_MAINTENANCE_INTERVAL_MINUTES=N`
  (timer). In multi-agent setups, prefer running this in the single daemon.

## 9. Backup & restore

Oracle ships a **portable, Dart-native backup** — no `pg_dump` needed on the host. A backup is a plain
`.sql` **data seed** (all rows, embeddings included); the schema is owned by the migrations, so the seed
restores into a freshly-migrated database. The file is small, inspectable, and safe to commit — the shared
memory bank travels with the repo and restores identically anywhere.

**Make a backup** (CLI or the `oracle_maintenance_backup` tool):

```bash
oracle_ai backup-db                       # writes backups/oracle_seed.sql
oracle_ai backup-db path/to/seed.sql      # or a chosen path
```

**Restore** (only into an empty DB unless you force it — restore never truncates):

```bash
oracle_ai restore-db                      # backups/oracle_seed.sql -> empty DB
oracle_ai restore-db path/to/seed.sql --force
```

**Auto-restore on `docker compose up`.** Set `ORACLE_DB_SEED_PATH` (the compose files default it to
`/app/backups/oracle_seed.sql` and mount `./backups`). On a **fresh volume**, the boot-owning process
(`serve-hooks` / all-in-one) restores the seed **if the DB is empty** — bringing the stack up rehydrates the
saved memory. It never overwrites a populated database, and a per-agent `serve-mcp` never seeds (no
cold-start race). `ORACLE_DB_SEED_ON_EMPTY=false` disables it.

**Versioning a shared memory bank.** Seeds are git-ignored by default (they may hold sensitive content). To
commit one intentionally: `git add -f backups/oracle_seed.sql`. A teammate who clones and runs
`docker compose up` on a fresh volume gets the same memory.

Typical loop: `oracle_ai backup-db` → commit the seed → colleague pulls → `docker compose up` restores it.

## 10. Troubleshooting

| Symptom | Cause / action |
|---|---|
| `hooks HTTP not started (port in use…)` | Another process (agent) already owns the port — expected in multi-agent; it serves MCP anyway. |
| `migration lock held … retry` | Two processes starting together — it retries itself; a stale lock (crashed holder) is reclaimed after 2 min. |
| `database "oracle_ai" not found` | Start with `ORACLE_DB_AUTO_CREATE=true`, or run `oracle_ai migrate`. |
| Empty brief/recall on the first session | Normal — no handoff/rules/memories yet; populate via the tools. |
