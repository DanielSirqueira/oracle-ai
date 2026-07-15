-- =====================================================================
-- v2.1.0 — RFC (2/5): rfc_versions + rfc_sections.
-- Cada rodada de consolidação produz uma nova versão (padrão is_latest /
-- supersedes, igual a rules/memories). O corpo é SECCIONADO: cada seção do
-- checklist canônico é uma linha comentável e vetorizável, e o par
-- (required, coverage) é o que trava a conclusão quando algo está raso.
-- =====================================================================

CREATE TABLE IF NOT EXISTS rfc_versions (
    id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    rfc_id           uuid NOT NULL REFERENCES rfcs(id) ON DELETE CASCADE,
    version_no       integer NOT NULL,
    summary          text NOT NULL DEFAULT '',            -- resumo executável (substrato do embedding)
    embedding        vector(1024),
    embedding_model  text,
    fts              tsvector GENERATED ALWAYS AS
                     (to_tsvector('english', coalesce(summary, ''))) STORED,
    is_latest        boolean NOT NULL DEFAULT true,
    supersedes       uuid REFERENCES rfc_versions(id) ON DELETE SET NULL,
    author_agent     text NOT NULL DEFAULT 'claude-code', -- consolidador
    created_at       timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_rfc_versions_no
    ON rfc_versions (rfc_id, version_no);
CREATE UNIQUE INDEX IF NOT EXISTS uq_rfc_versions_latest
    ON rfc_versions (rfc_id) WHERE is_latest;
CREATE INDEX IF NOT EXISTS idx_rfc_versions_rfc ON rfc_versions (rfc_id);
CREATE INDEX IF NOT EXISTS idx_rfc_versions_fts ON rfc_versions USING gin (fts);
CREATE INDEX IF NOT EXISTS idx_rfc_versions_embedding ON rfc_versions
    USING hnsw (embedding vector_cosine_ops) WITH (m = 16, ef_construction = 64);

-- Fecha o ciclo rfcs <-> rfc_versions agora que rfc_versions existe.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'rfcs_current_version_fk'
  ) THEN
    ALTER TABLE rfcs ADD CONSTRAINT rfcs_current_version_fk
      FOREIGN KEY (current_version_id) REFERENCES rfc_versions(id) ON DELETE SET NULL;
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS rfc_sections (
    id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    version_id       uuid NOT NULL REFERENCES rfc_versions(id) ON DELETE CASCADE,
    section_key      text NOT NULL,                       -- context|problem|goals|scope|functional_reqs|
                                                          -- nonfunctional_reqs|business_rules|flows|ui_behavior|
                                                          -- architecture|data_model|integrations|security|
                                                          -- observability|migration|tests|acceptance_criteria|
                                                          -- risks|open_decisions|alternatives|dependencies|cross_module_impact
    content          text NOT NULL DEFAULT '',
    required         boolean NOT NULL DEFAULT false,      -- exigida pelo rfc_type
    coverage         text NOT NULL DEFAULT 'missing'
                     CHECK (coverage IN ('missing','thin','covered')),
    embedding        vector(1024),
    embedding_model  text,
    fts              tsvector GENERATED ALWAYS AS
                     (to_tsvector('english', coalesce(content, ''))) STORED,
    created_at       timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_rfc_sections_key
    ON rfc_sections (version_id, section_key);
CREATE INDEX IF NOT EXISTS idx_rfc_sections_version ON rfc_sections (version_id);
CREATE INDEX IF NOT EXISTS idx_rfc_sections_fts ON rfc_sections USING gin (fts);
CREATE INDEX IF NOT EXISTS idx_rfc_sections_embedding ON rfc_sections
    USING hnsw (embedding vector_cosine_ops) WITH (m = 16, ef_construction = 64);
