-- =====================================================================
-- Skills: a centralized, versioned library of agent skills (SKILL.md-style
-- procedural know-how). One shared source of truth — agents fetch skills by
-- context over MCP (search/get) instead of duplicating files per agent
-- folder; `sync-skills` can materialize them for native discovery.
--
-- Scope: a skill belongs to a project, OR a product, OR is GLOBAL (both
-- null) — unlike rules/memories, ecosystem-wide skills are the common case.
-- Versioning mirrors rules: stable `key` + is_latest/supersedes.
-- Additive, forward-only; guarded so it is safe to re-run.
-- =====================================================================

CREATE TABLE IF NOT EXISTS skills (
    id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id       uuid REFERENCES products(id) ON DELETE CASCADE,
    project_id       uuid REFERENCES projects(id) ON DELETE CASCADE,
    key              text NOT NULL,                                  -- stable slug (folder name)
    name             text NOT NULL,                                  -- display name
    description      text NOT NULL,                                  -- when to use (the recall trigger)
    content          text NOT NULL,                                  -- SKILL.md body (markdown)
    tags             text[] NOT NULL DEFAULT '{}',
    embedding        vector(1024),
    embedding_model  text,
    fts              tsvector GENERATED ALWAYS AS
                     (to_tsvector('english', coalesce(name, '') || ' ' ||
                      coalesce(description, '') || ' ' || coalesce(content, ''))) STORED,
    is_latest        boolean NOT NULL DEFAULT true,
    supersedes       uuid REFERENCES skills(id) ON DELETE SET NULL,
    retired_at       timestamptz,
    retired_reason   text,
    access_count     integer NOT NULL DEFAULT 0,
    last_accessed_at timestamptz,
    created_at       timestamptz NOT NULL DEFAULT now(),
    updated_at       timestamptz NOT NULL DEFAULT now()
);

-- One current version per (owner, key) — project, product, or global.
CREATE UNIQUE INDEX IF NOT EXISTS uq_skills_project_key_latest
    ON skills (project_id, key)
    WHERE is_latest AND project_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_skills_product_key_latest
    ON skills (product_id, key)
    WHERE is_latest AND project_id IS NULL AND product_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_skills_global_key_latest
    ON skills (key)
    WHERE is_latest AND project_id IS NULL AND product_id IS NULL;

-- Hybrid search legs: lexical (GIN over fts) + semantic (HNSW, cosine).
CREATE INDEX IF NOT EXISTS idx_skills_fts ON skills USING gin (fts);
CREATE INDEX IF NOT EXISTS idx_skills_embedding ON skills
    USING hnsw (embedding vector_cosine_ops) WITH (m = 16, ef_construction = 64);
