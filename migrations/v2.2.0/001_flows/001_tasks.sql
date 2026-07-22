-- =====================================================================
-- v2.2.0 — Loop Engineering (1/4): tasks (o backlog que aciona fluxos).
-- Uma task é uma demanda de desenvolvimento. Ancora em exatamente um nível de
-- escopo (organization / project / module), igual a rfcs/rules/memories, e pode
-- apontar para a RFC que a especifica. É o gatilho: criar uma task e escolher um
-- flow dispara o ciclo completo (ver [[loop-engineering-plan]]). Vetorizada para
-- dedup semântico ("isso já foi pedido?", reusando o padrão de request_search).
-- =====================================================================

CREATE TABLE IF NOT EXISTS tasks (
    id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id  uuid REFERENCES organizations(id) ON DELETE CASCADE,
    project_id       uuid REFERENCES projects(id)      ON DELETE CASCADE,
    module_id        uuid REFERENCES modules(id)       ON DELETE CASCADE,
    title            text NOT NULL,
    description      text NOT NULL DEFAULT '',
    status           text NOT NULL DEFAULT 'backlog'
                     CHECK (status IN ('backlog','ready','running','blocked','done','cancelled')),
    priority         integer NOT NULL DEFAULT 50
                     CHECK (priority BETWEEN 0 AND 100),   -- 0..100, como rules.priority
    source           text NOT NULL DEFAULT 'human'
                     CHECK (source IN ('human','agent','flow')),
    rfc_id           uuid REFERENCES rfcs(id) ON DELETE SET NULL,  -- spec quando houver
    created_by       text NOT NULL DEFAULT 'human',        -- humano | nome do agente
    embedding        vector(1024),
    embedding_model  text,
    fts              tsvector GENERATED ALWAYS AS
                     (to_tsvector('english', coalesce(title, '') || ' ' || coalesce(description, ''))) STORED,
    created_at       timestamptz NOT NULL DEFAULT now(),
    updated_at       timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT tasks_owner_check
        CHECK (organization_id IS NOT NULL OR project_id IS NOT NULL OR module_id IS NOT NULL)
);

CREATE INDEX IF NOT EXISTS idx_tasks_organization ON tasks (organization_id);
CREATE INDEX IF NOT EXISTS idx_tasks_project      ON tasks (project_id);
CREATE INDEX IF NOT EXISTS idx_tasks_module       ON tasks (module_id);
CREATE INDEX IF NOT EXISTS idx_tasks_status       ON tasks (status, updated_at);
CREATE INDEX IF NOT EXISTS idx_tasks_rfc          ON tasks (rfc_id);
CREATE INDEX IF NOT EXISTS idx_tasks_fts ON tasks USING gin (fts);
CREATE INDEX IF NOT EXISTS idx_tasks_embedding ON tasks
    USING hnsw (embedding vector_cosine_ops) WITH (m = 16, ef_construction = 64);
