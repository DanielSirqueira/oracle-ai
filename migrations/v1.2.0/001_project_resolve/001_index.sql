-- ============================================================
-- Resolve-or-create a project by its repository path (the agent's cwd).
-- ============================================================
-- A plain UNIQUE index treats NULLs as distinct, so projects without a
-- repo_path are unaffected, while non-null paths become unique. This enables
-- a race-safe `INSERT ... ON CONFLICT (repo_path) DO UPDATE` upsert across
-- concurrently-starting agents (Claude Code, Codex, ...) and fast cwd lookups,
-- so an agent can map its working directory to a stable projectId.
CREATE UNIQUE INDEX IF NOT EXISTS uq_projects_repo_path ON projects (repo_path);
