-- =====================================================================
-- v2.0.0 — Restructure (2/8): modules under projects.
-- A project has many modules (a service, a layer, a package). Agents were
-- creating modules as if they were separate projects, polluting the project's
-- metrics and views; a module is now a first-class child of a project.
-- `path` is the subpath under the repo root, used to auto-resolve the module
-- from the agent's cwd (oracle_module_resolve).
-- =====================================================================

CREATE TABLE IF NOT EXISTS modules (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id  uuid NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    key         text NOT NULL,                 -- stable slug
    name        text NOT NULL,
    path        text,                          -- subpath under the repo root (auto-resolve)
    description text,
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now(),
    UNIQUE (project_id, key)
);

CREATE INDEX IF NOT EXISTS idx_modules_project ON modules (project_id);
-- One module per (project, path) so cwd auto-resolution is unambiguous.
CREATE UNIQUE INDEX IF NOT EXISTS uq_modules_project_path
    ON modules (project_id, path) WHERE path IS NOT NULL;
