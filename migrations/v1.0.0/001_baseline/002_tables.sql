-- Oracle AI — baseline / tables
-- Embedding dimension: 1024 (voyage-code-3 / Qwen3). Change here if the model changes.
-- IDs use gen_random_uuid() (UUIDv4, native PG13+).

-- ============================================================
-- Scope hierarchy: ecosystem -> product -> project
-- ============================================================

CREATE TABLE products (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name        text NOT NULL,
    description text,
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE projects (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id  uuid REFERENCES products(id) ON DELETE SET NULL,  -- nullable: a project may be standalone
    name        text NOT NULL,
    description text,
    repo_path   text,                                             -- absolute path to match the agent cwd
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now(),
    UNIQUE (product_id, name)
);

-- ============================================================
-- Project knowledge: architecture, rules (versioned)
-- ============================================================

CREATE TABLE architectures (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id      uuid NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    area            text NOT NULL,                                -- module / layer
    content         text NOT NULL,
    embedding       vector(1024),
    embedding_model text,
    is_latest       boolean NOT NULL DEFAULT true,
    supersedes      uuid REFERENCES architectures(id) ON DELETE SET NULL,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE rules (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id      uuid REFERENCES products(id) ON DELETE CASCADE,  -- PRODUCT-wide rule (inherited) ...
    project_id      uuid REFERENCES projects(id) ON DELETE CASCADE,  -- ... OR PROJECT-specific (override)
    key             text NOT NULL,                                   -- stable slug for supersession
    scope           text NOT NULL,                                   -- module / folder / area (e.g. 'controllers')
    title           text NOT NULL,
    content         text NOT NULL,
    severity        text NOT NULL DEFAULT 'recommended'
                    CHECK (severity IN ('required', 'recommended')),
    tags            text[] NOT NULL DEFAULT '{}',
    embedding       vector(1024),
    embedding_model text,
    fts             tsvector GENERATED ALWAYS AS
                    (to_tsvector('english', coalesce(title, '') || ' ' || coalesce(content, ''))) STORED,
    is_latest       boolean NOT NULL DEFAULT true,
    supersedes      uuid REFERENCES rules(id) ON DELETE SET NULL,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    CHECK (product_id IS NOT NULL OR project_id IS NOT NULL)         -- belongs to a product OR a project
);

-- ============================================================
-- Sessions and raw capture: history, requests, agent events
-- ============================================================

-- A session IS the agent's own session (Claude Code / Codex / Cursor / ...).
-- Identified by the agent's session id (`external_id`, from the hook payload);
-- no status/lifecycle — the agent resumes the same session whenever it wants.
CREATE TABLE sessions (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id  uuid NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    agent       text NOT NULL,                                    -- claude-code / codex / cursor ...
    external_id text,                                             -- the agent's OWN session id (hook session_id)
    cwd         text,
    created_at  timestamptz NOT NULL DEFAULT now(),
    UNIQUE (project_id, agent, external_id)                       -- the agent's session id is the identity
);

-- A request is one USER DEMAND: each user prompt opens a new request. Its
-- user_text is the prompt itself (embedded + full-text indexed, so past demands
-- are semantically searchable). The agent's work is the messages under it.
CREATE TABLE requests (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id uuid NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    user_text  text NOT NULL,                                     -- the user's prompt (the demand)
    embedding  vector(1024),
    fts        tsvector GENERATED ALWAYS AS (to_tsvector('english', coalesce(user_text, ''))) STORED,
    created_at timestamptz NOT NULL DEFAULT now()
);

-- A message belongs to a REQUEST (not directly to a session) — it is the agent's
-- work (assistant/tool turns) carrying out that request.
CREATE TABLE messages (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    request_id  uuid NOT NULL REFERENCES requests(id) ON DELETE CASCADE,
    role        text NOT NULL CHECK (role IN ('user', 'assistant', 'tool', 'system')),
    content     text NOT NULL,
    token_count integer,
    embedding   vector(1024),                                     -- nullable: low-signal turns stay unembedded
    created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE agent_events (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    request_id  uuid NOT NULL REFERENCES requests(id) ON DELETE CASCADE,
    kind        text NOT NULL CHECK (kind IN ('step', 'reasoning', 'query', 'decision', 'action')),
    content     text NOT NULL,
    position    integer,
    embedding   vector(1024),                                     -- nullable
    created_at  timestamptz NOT NULL DEFAULT now()
);

-- ============================================================
-- Consolidated memory (written by the AGENT via oracle_memory_save)
-- ============================================================

CREATE TABLE memories (
    id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id        uuid REFERENCES products(id) ON DELETE CASCADE,  -- PRODUCT memory (cross-repo) ...
    project_id        uuid REFERENCES projects(id) ON DELETE CASCADE,  -- ... OR PROJECT memory
    tier              text NOT NULL CHECK (tier IN ('episodic', 'semantic', 'procedural')),
    kind              text NOT NULL CHECK (kind IN ('decision', 'gotcha', 'rule', 'fact')),
    title             text NOT NULL,
    body              text NOT NULL,
    tags              text[] NOT NULL DEFAULT '{}',
    importance        real NOT NULL DEFAULT 0,
    embedding         vector(1024),
    embedding_model   text,
    fts               tsvector GENERATED ALWAYS AS
                      (to_tsvector('english', coalesce(title, '') || ' ' || coalesce(body, ''))) STORED,
    is_latest         boolean NOT NULL DEFAULT true,
    supersedes        uuid REFERENCES memories(id) ON DELETE SET NULL,
    superseded_at     timestamptz,
    access_count      integer NOT NULL DEFAULT 0,
    last_accessed_at  timestamptz,
    origin_session_id uuid REFERENCES sessions(id) ON DELETE SET NULL,   -- provenance
    origin_request_id uuid REFERENCES requests(id) ON DELETE SET NULL,
    created_at        timestamptz NOT NULL DEFAULT now(),
    updated_at        timestamptz NOT NULL DEFAULT now(),
    CHECK (product_id IS NOT NULL OR project_id IS NOT NULL)
);

-- ============================================================
-- Handoff (continuity across sessions / agents)
-- ============================================================

CREATE TABLE handoffs (
    id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id        uuid NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    source_session_id uuid REFERENCES sessions(id) ON DELETE SET NULL,
    from_agent        text,
    to_agent          text,
    summary           text NOT NULL,
    open_questions    jsonb NOT NULL DEFAULT '[]',
    next_steps        jsonb NOT NULL DEFAULT '[]',
    files_touched     jsonb NOT NULL DEFAULT '[]',
    status            text NOT NULL DEFAULT 'open'
                      CHECK (status IN ('open', 'accepted', 'expired')),
    cwd               text,
    created_at        timestamptz NOT NULL DEFAULT now(),
    accepted_at       timestamptz
);
