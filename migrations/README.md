# Oracle AI — Database Migrations

Versioned, file-based SQL migrations applied by the `oracle_migration` package.
The MCP server runs the pending migrations on startup, so the schema is always
up to date.

## Layout

```
migrations/
  migration_lock.yaml          # tooling marker (managed)
  v1.0.0/
    001_baseline/
      001_create_extensions.sql
      002_create_tables.sql
      003_create_indexes.sql
    002_seed/
      001_seed.sql
  v1.1.0/
    001_add_xyz/
      001_alter.sql
```

- **Version** (`vMAJOR.MINOR.PATCH`): a semver release of the schema.
- **Migration** (`<seq>_<name>`): one unit of change; runs in a single
  transaction (all its files together — all-or-nothing).
- **SQL files** (`<seq>_<name>.sql`): numbered steps, executed in order.

## Rules

- Migrations are **append-only**. Never edit an applied migration — its checksum
  is recorded and `verify` will flag drift. To fix a mistake, add a new
  migration (forward-fix).
- One transaction per migration: if any file fails, the whole migration rolls
  back. The attempt is still recorded in `_migrations` (status `failed`).

## Control tables (auto-created)

- `_migrations` — history of applied/failed migrations (version, sequence,
  checksum, status, timing).
- `_migrations_lock` — single-row advisory lock preventing concurrent runs.

> The schema SQL itself (PostgreSQL + pgvector tables) lands here as
> `v1.0.0/001_baseline/...` once the data model is finalized.
